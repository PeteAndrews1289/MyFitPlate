'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { runMigrations, discoverMigrations, META_COLLECTION } = require('../migrate');
const { FakeFirestore } = require('./fakeFirestore');
const example0001 = require('../migrations/0001_backfill_schema_version');

const migration = (id, up) => ({ id, name: `test ${id}`, up });

test('discoverMigrations finds and orders the real migrations', () => {
  const found = discoverMigrations();
  assert.ok(found.length >= 1, 'at least the example migration is present');
  assert.equal(found[0].id, '0001');
  const ids = found.map((m) => m.id);
  assert.deepEqual(ids, [...ids].sort(), 'migrations are returned in ascending id order');
});

test('applies a pending migration and records it', async () => {
  const db = new FakeFirestore();
  let ran = 0;
  const migrations = [migration('0001', async () => { ran += 1; return 3; })];

  const { ok, results } = await runMigrations(db, { migrations });

  assert.equal(ok, true);
  assert.equal(ran, 1);
  assert.equal(results[0].status, 'applied');
  assert.equal(results[0].changed, 3);

  const meta = await db.collection(META_COLLECTION).doc('0001').get();
  assert.equal(meta.exists, true, 'applied migration is recorded');
  assert.equal(meta.data().changed, 3);
});

test('is idempotent — a second run skips already-applied migrations', async () => {
  const db = new FakeFirestore();
  let ran = 0;
  const migrations = [migration('0001', async () => { ran += 1; return 1; })];

  await runMigrations(db, { migrations });
  const second = await runMigrations(db, { migrations });

  assert.equal(ran, 1, 'up() must not run a second time');
  assert.equal(second.results[0].status, 'skipped');
});

test('dry-run computes changes without writing data or recording', async () => {
  const db = new FakeFirestore();
  let ran = 0;
  const migrations = [migration('0001', async (_db, ctx) => {
    ran += 1;
    assert.equal(ctx.dryRun, true, 'dryRun is passed through to the migration');
    return 5;
  })];

  const { results } = await runMigrations(db, { migrations, dryRun: true });

  assert.equal(ran, 1);
  assert.equal(results[0].status, 'would-apply');
  const meta = await db.collection(META_COLLECTION).doc('0001').get();
  assert.equal(meta.exists, false, 'dry-run must not record the migration');
});

test('stops on the first failing migration; does not record or continue', async () => {
  const db = new FakeFirestore();
  let secondRan = false;
  const migrations = [
    migration('0001', async () => { throw new Error('boom'); }),
    migration('0002', async () => { secondRan = true; return 0; }),
  ];

  const { ok, results } = await runMigrations(db, { migrations });

  assert.equal(ok, false);
  assert.equal(results[0].status, 'failed');
  assert.match(results[0].error, /boom/);
  assert.equal(secondRan, false, 'later migrations must not run after a failure');
  const meta = await db.collection(META_COLLECTION).doc('0001').get();
  assert.equal(meta.exists, false, 'a failed migration must not be recorded');
});

test('example 0001 backfills only docs missing schemaVersion, idempotently', async () => {
  const db = new FakeFirestore({
    users: {
      u1: { name: 'A' },
      u2: { name: 'B', schemaVersion: 1 },
      u3: { name: 'C' },
    },
  });

  const changed = await example0001.up(db, { dryRun: false, log: () => {} });

  assert.equal(changed, 2, 'u1 and u3 backfilled; u2 already had it');
  assert.equal((await db.collection('users').doc('u1').get()).data().schemaVersion, 1);
  assert.equal((await db.collection('users').doc('u3').get()).data().schemaVersion, 1);
  assert.equal((await db.collection('users').doc('u1').get()).data().name, 'A', 'merge preserves existing fields');

  const again = await example0001.up(db, { dryRun: false, log: () => {} });
  assert.equal(again, 0, 're-running is a no-op');
});

test('example 0001 dry-run reports changes but writes nothing', async () => {
  const db = new FakeFirestore({ users: { u1: { name: 'A' } } });

  const changed = await example0001.up(db, { dryRun: true, log: () => {} });

  assert.equal(changed, 1);
  assert.equal(
    (await db.collection('users').doc('u1').get()).data().schemaVersion,
    undefined,
    'dry-run leaves data untouched'
  );
});
