# MyFitPlate Data Safety

The app holds real users' health and nutrition data in Firestore. This doc covers the
two safety nets that keep that data recoverable and changes non-destructive:

1. **Backups** — so data can always be restored.
2. **Migrations** — so schema changes are reviewed, idempotent, and reversible-by-restore
   instead of ad-hoc batch writes that can silently corrupt production.

**The one rule:** never run an ad-hoc script or console batch-write against production data.
Every data change goes through a reviewed migration, and every production migration is
preceded by a backup.

---

## 1. Backups

### Automated (recommended): native scheduled backups
Google-managed, no code. Set once per database:

```bash
# Daily backups, kept 7 days:
gcloud firestore backups schedules create \
  --project=caloriebeta-d28de \
  --database='(default)' \
  --recurrence=daily \
  --retention=7d

# Verify / list:
gcloud firestore backups schedules list --database='(default)' --project=caloriebeta-d28de
```

Restore from a managed backup creates a *new* database you can verify before swapping:

```bash
gcloud firestore backups list --project=caloriebeta-d28de
gcloud firestore databases restore \
  --source-backup=projects/caloriebeta-d28de/locations/LOCATION/backups/BACKUP_ID \
  --destination-database='restored-YYYYMMDD'
```

### On-demand (before a migration): export to GCS

```bash
scripts/firestore-backup.sh                 # exports to gs://caloriebeta-d28de-firestore-backups/manual/<timestamp>
scripts/firestore-backup.sh gs://my-bucket  # or a bucket you choose
```

Restore an export:

```bash
gcloud firestore import gs://.../manual/<timestamp> --project=caloriebeta-d28de --database='(default)'
```

> Keep at least one automated schedule **and** take an on-demand export immediately before any
> production migration. Backups are only real once you have tested a restore at least once.

---

## 2. Migrations

Tooling lives in `tools/firestore-migrate/`. The runner is versioned, idempotent, dry-runnable,
and records every applied migration in a `_migrations` collection, so it never double-applies.

### Write a migration
Copy `migrations/0001_backfill_schema_version.js`, bump the numeric prefix, and keep `up`
**idempotent** (safe to run twice) — only touch documents that actually need changing, and
return the number changed:

```js
module.exports = {
  id: '0002',
  name: 'short description',
  async up(db, { dryRun, log }) {
    const snap = await db.collection('users').get();
    let changed = 0;
    for (const doc of snap.docs) {
      if (/* needs change */ false) {
        if (!dryRun) await doc.ref.set({ /* ... */ }, { merge: true });
        changed += 1;
      }
    }
    log(`changed ${changed}`);
    return changed;
  },
};
```

### Test it (no emulator/Java needed)
The runner is unit-tested against an in-memory fake Firestore:

```bash
cd tools/firestore-migrate
node --test test/*.test.js
```

Add a test for your migration's logic in `test/migrate.test.js` using `FakeFirestore`.

### Run it
Order of operations, every time:

```bash
cd tools/firestore-migrate
npm install                 # one-time: installs firebase-admin for real runs

# 1. Against the local emulator (safe; needs Java + `firebase emulators:start`):
npm run migrate:dry         # see what WOULD change
npm run migrate:emulator    # apply against the emulator

# 2. Against production — ONLY after a backup:
scripts/firestore-backup.sh
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
node migrate.js --prod --dry-run                 # preview prod changes
node migrate.js --prod --yes-i-took-a-backup     # apply
```

The runner **refuses** to touch production without both a service-account key and the
`--yes-i-took-a-backup` flag. It stops on the first failing migration and never records a
partial apply — so a failure leaves a clean, restorable state.

---

## CI
`tools/firestore-migrate` runs in CI as the **Data migrations** job (`node --test`, no emulator),
so a broken runner or a non-idempotent example migration fails the build before it can reach `main`.
