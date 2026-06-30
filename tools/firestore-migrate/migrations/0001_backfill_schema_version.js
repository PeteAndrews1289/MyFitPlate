'use strict';

// Example, production-safe migration. Stamps every user document with a
// `schemaVersion` so future migrations can target specific shapes. Idempotent:
// it only writes docs that are missing the field, so re-running is a no-op.
//
// Copy this file's shape for new migrations: bump the numeric prefix, keep `up`
// idempotent, return the number of docs changed, and respect `dryRun`.

module.exports = {
  id: '0001',
  name: 'backfill schemaVersion on user docs',

  async up(db, { dryRun, log }) {
    const snap = await db.collection('users').get();
    let changed = 0;

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      if (data.schemaVersion === undefined) {
        if (!dryRun) await doc.ref.set({ schemaVersion: 1 }, { merge: true });
        changed += 1;
      }
    }

    log(`${dryRun ? 'would set' : 'set'} schemaVersion on ${changed} user doc(s)`);
    return changed;
  },
};
