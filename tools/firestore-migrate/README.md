# firestore-migrate

Versioned, idempotent Firestore migration runner for MyFitPlate. See the full runbook in
[`docs/data-safety.md`](../../docs/data-safety.md).

## Quick start

```bash
node --test test/*.test.js     # run the test suite (zero deps, no emulator)

npm install                    # one-time, for real runs (pulls firebase-admin)
npm run migrate:dry            # preview against the emulator
npm run migrate:emulator       # apply against the emulator
```

Production runs require a backup first and explicit flags:

```bash
../../scripts/firestore-backup.sh
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
node migrate.js --prod --yes-i-took-a-backup
```

## Layout
- `migrate.js` — the runner (pure logic + a guarded CLI).
- `migrations/NNNN_*.js` — one file per migration: `{ id, name, async up(db, ctx) }`. Keep `up` idempotent.
- `test/` — `node:test` suite driven by an in-memory `FakeFirestore`.

## Rules
- Every data change is a migration here — never an ad-hoc batch write to production.
- `up` must be safe to run twice. Return the number of documents changed.
- Honour `ctx.dryRun`: compute and log, but do not write.
