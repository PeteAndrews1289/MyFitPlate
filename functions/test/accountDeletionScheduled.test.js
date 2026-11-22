const test = require("node:test");
const assert = require("node:assert/strict");
process.env.GCLOUD_PROJECT = "demo-myfitplate-deletion-pure";
const { purgeCompletedAccountDeletionBarriers } = require("../lib/index.js");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

test("an undelivered hourly recovery request retries after the worker has time to start", () => {
  const trigger = purgeCompletedAccountDeletionBarriers.__endpoint.scheduleTrigger;
  assert.equal(trigger.schedule, "every 60 minutes");
  assert.equal(trigger.retryConfig.retryCount, 3);
  assert.equal(trigger.retryConfig.minBackoffSeconds, 60);
  assert.equal(trigger.retryConfig.maxBackoffSeconds, 240);
  assert.equal(trigger.retryConfig.maxDoublings, 2);
});

test("scheduled deletion resumes accepted intent, recovers absent Auth, bounds work and rechecks purge state", async () => {
  const db = getFirestore(), auth = getAuth();
  const originals = { collection: db.collection, recursiveDelete: db.recursiveDelete,
    runTransaction: db.runTransaction, deleteUser: auth.deleteUser };
  const events = [], limits = [], completed = [], deleted = [];
  const pendingRef = { path: "accountDeletionBarriers/pending-owner",
    update: async value => { events.push("retry-reserved"); assert.ok(value.nextAttemptAt.toMillis() > Date.now()); },
    set: async value => { events.push("complete"); completed.push(value); } };
  const expiredRef = { path: "accountDeletionBarriers/expired-owner" };
  const renewedRef = { path: "accountDeletionBarriers/renewed-owner" };
  try {
    db.collection = collection => ({
      doc: id => ({ path: `${collection}/${id}` }),
      where: field => ({ limit: count => {
        limits.push(count);
        return { get: async () => ({ docs: field === "nextAttemptAt"
          ? [{ id: "pending-owner", ref: pendingRef, data: () => ({ status: "deleting" }) }]
          : [{ ref: expiredRef }, { ref: renewedRef }] }) };
      }, get: async () => ({ docs: [], empty: true }) }),
    });
    db.recursiveDelete = async ref => { assert.equal(ref.path, "users/pending-owner"); events.push("data-erased"); };
    auth.deleteUser = async uid => { assert.equal(uid, "pending-owner"); events.push("auth-already-gone"); throw { code: "auth/user-not-found" }; };
    db.runTransaction = async operation => operation({
      get: async ref => ({ data: () => ref === renewedRef ? { status: "deleting" }
        : { status: "complete", expiresAt: Timestamp.fromMillis(1) } }),
      delete: ref => deleted.push(ref.path),
    });
    await purgeCompletedAccountDeletionBarriers.run({ scheduleTime: new Date().toISOString() });
    assert.deepEqual(limits, [10, 250]);
    assert.deepEqual(events, ["retry-reserved", "data-erased", "auth-already-gone", "complete"]);
    assert.equal(completed[0].status, "complete");
    assert.ok(completed[0].expiresAt.toMillis() > Date.now() + 47 * 60 * 60 * 1000);
    assert.deepEqual(deleted, [expiredRef.path], "A barrier renewed after the query must not be purged");
  } finally {
    Object.assign(db, { collection: originals.collection, recursiveDelete: originals.recursiveDelete, runTransaction: originals.runTransaction });
    auth.deleteUser = originals.deleteUser;
  }
});
