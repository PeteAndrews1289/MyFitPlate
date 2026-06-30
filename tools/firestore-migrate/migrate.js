'use strict';

// Versioned, idempotent Firestore migration runner.
//
// Why this exists: ad-hoc batch writes are the single biggest data-loss risk for a
// live app. A migration here is reviewed, ordered, idempotent, dry-runnable, and
// records what it did — so schema changes can't silently corrupt production data.
//
// The runner is pure logic over an injected Firestore `db`, so it is fully unit-tested
// against an in-memory fake (no emulator/Java needed). The CLI at the bottom wires it
// to the real Admin SDK (emulator by default; prod only behind explicit guards).

const fs = require('fs');
const path = require('path');

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');
// Each applied migration is recorded as one doc in this collection (doc id = migration id).
const META_COLLECTION = '_migrations';

/** Load + validate migration modules from disk, sorted by their numeric prefix. */
function discoverMigrations(dir = MIGRATIONS_DIR) {
  const files = fs
    .readdirSync(dir)
    .filter((f) => /^\d{4}_.+\.js$/.test(f))
    .sort();

  const migrations = files.map((file) => {
    const mod = require(path.join(dir, file));
    if (!mod || mod.id == null || typeof mod.up !== 'function') {
      throw new Error(`Migration "${file}" must export { id, name, async up(db, ctx) }`);
    }
    if (String(mod.id) !== file.slice(0, 4)) {
      throw new Error(`Migration "${file}" id "${mod.id}" must match its filename prefix`);
    }
    return { file, id: String(mod.id), name: mod.name || file, up: mod.up };
  });

  const ids = migrations.map((m) => m.id);
  const dupes = ids.filter((id, i) => ids.indexOf(id) !== i);
  if (dupes.length) throw new Error(`Duplicate migration ids: ${[...new Set(dupes)].join(', ')}`);
  return migrations;
}

/** Set of migration ids already recorded as applied. */
async function appliedIds(db) {
  const snap = await db.collection(META_COLLECTION).get();
  const set = new Set();
  snap.forEach((doc) => set.add(doc.id));
  return set;
}

/**
 * Run all pending migrations in order.
 * @param db Firestore instance (real Admin SDK or the in-memory fake)
 * @param opts.dryRun  compute + log changes without writing or recording (default false)
 * @param opts.log     logger (default no-op)
 * @param opts.migrations  pre-built list (tests); otherwise discovered from disk
 * @returns { ok, results } — stops on the first failing migration
 */
async function runMigrations(db, opts = {}) {
  const { dryRun = false, log = () => {}, migrationsDir, migrations: provided } = opts;
  const migrations = provided || discoverMigrations(migrationsDir);
  const applied = await appliedIds(db);
  const results = [];

  for (const m of migrations) {
    if (applied.has(m.id)) {
      results.push({ id: m.id, status: 'skipped' });
      continue;
    }

    log(`${dryRun ? '[dry-run] ' : ''}applying ${m.id} — ${m.name}`);
    const ctx = { dryRun, log: (msg) => log(`  ${m.id}: ${msg}`) };

    let changed = 0;
    try {
      changed = (await m.up(db, ctx)) || 0;
    } catch (err) {
      // Stop immediately — never record a half-applied migration, never run later ones.
      results.push({ id: m.id, status: 'failed', error: err.message });
      log(`  ${m.id}: FAILED — ${err.message}`);
      return { ok: false, results };
    }

    if (!dryRun) {
      await db.collection(META_COLLECTION).doc(m.id).set({
        id: m.id,
        name: m.name,
        appliedAt: new Date().toISOString(),
        changed,
      });
    }

    results.push({ id: m.id, status: dryRun ? 'would-apply' : 'applied', changed });
  }

  return { ok: true, results };
}

module.exports = { runMigrations, discoverMigrations, appliedIds, META_COLLECTION, MIGRATIONS_DIR };

// ---------------------------------------------------------------------------
// CLI. Safe by default: targets the local emulator unless --prod is given, and
// --prod refuses to run without service-account credentials AND a backup ack.
// ---------------------------------------------------------------------------
if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const dryRun = args.includes('--dry-run');
    const prod = args.includes('--prod');

    let admin;
    try {
      admin = require('firebase-admin');
    } catch {
      console.error('firebase-admin is not installed. Run `npm install firebase-admin` in tools/firestore-migrate.');
      process.exit(1);
    }

    if (prod) {
      if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
        console.error('Refusing to run against prod: set GOOGLE_APPLICATION_CREDENTIALS to a service-account key first.');
        process.exit(1);
      }
      if (!args.includes('--yes-i-took-a-backup')) {
        console.error('Refusing to run against prod without --yes-i-took-a-backup. Run scripts/firestore-backup.sh first.');
        process.exit(1);
      }
      admin.initializeApp();
      console.log('Target: PRODUCTION Firestore.');
    } else {
      process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080';
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'caloriebeta-d28de' });
      console.log(`Target: Firestore emulator at ${process.env.FIRESTORE_EMULATOR_HOST}.`);
    }

    const db = admin.firestore();
    const { ok, results } = await runMigrations(db, { dryRun, log: console.log });

    console.log('\nSummary:');
    for (const r of results) {
      const extra = r.changed != null ? ` (${r.changed} changed)` : r.error ? ` — ${r.error}` : '';
      console.log(`  ${r.id}: ${r.status}${extra}`);
    }
    process.exit(ok ? 0 : 1);
  })().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
