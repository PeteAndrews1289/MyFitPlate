const test = require("node:test");
const assert = require("node:assert/strict");
const { requireExpectedDeletionOwner, runDeletionWithBarrier, canPurgeDeletionBarrier,
  COMPLETED_DELETION_RETENTION_MS } = require("../lib/accountDeletion.js");

test("deletion owner rejects switched or malformed accounts and preserves legacy API", () => {
  assert.doesNotThrow(() => requireExpectedDeletionOwner("owner", undefined));
  assert.doesNotThrow(() => requireExpectedDeletionOwner("owner", "owner"));
  assert.throws(() => requireExpectedDeletionOwner("new-owner", "old-owner"), { code: "permission-denied" });
  for (const value of ["", null, 4, {}]) assert.throws(() => requireExpectedDeletionOwner("owner", value), { code: "invalid-argument" });
});

test("barrier precedes deletion and Auth comes after successful data cleanup", async () => {
  const events = [];
  await runDeletionWithBarrier({
    begin: async () => events.push("barrier"), eraseData: async () => events.push("data"),
    eraseAuth: async () => events.push("auth"), complete: async () => events.push("completed-with-expiry"),
  });
  assert.deepEqual(events, ["barrier", "data", "auth", "completed-with-expiry"]);
});

test("data failure retains pending barrier and retry can finish without duplicate identity", async () => {
  let barrier = false, authDeleted = false, completed = false;
  const operations = {
    begin: async () => { barrier = true; }, eraseData: async () => { throw new Error("synthetic failure"); },
    eraseAuth: async () => { authDeleted = true; }, complete: async () => { completed = true; },
  };
  await assert.rejects(runDeletionWithBarrier(operations));
  assert.equal(barrier, true); assert.equal(authDeleted, false); assert.equal(completed, false);
  operations.eraseData = async () => {};
  await runDeletionWithBarrier(operations);
  assert.equal(authDeleted, true); assert.equal(completed, true);
});

test("lost completion after Auth deletion is recoverable with already-missing Auth", async () => {
  let finished = false;
  await runDeletionWithBarrier({ begin: async () => {}, eraseData: async () => {},
    eraseAuth: async () => { throw { code: "auth/user-not-found" }; }, complete: async () => { finished = true; } });
  assert.equal(finished, true);
  await assert.rejects(runDeletionWithBarrier({ begin: async () => {}, eraseData: async () => {},
    eraseAuth: async () => { throw { code: "auth/internal-error" }; }, complete: async () => assert.fail("not completed") }));
});

test("only completed expired barriers can be purged; unresolved deletion never expires", () => {
  assert.ok(COMPLETED_DELETION_RETENTION_MS > 60 * 60 * 1000);
  assert.equal(canPurgeDeletionBarrier("deleting", 1, 100), false);
  assert.equal(canPurgeDeletionBarrier("complete", undefined, 100), false);
  assert.equal(canPurgeDeletionBarrier("complete", NaN, 100), false);
  assert.equal(canPurgeDeletionBarrier("complete", 101, 100), false);
  assert.equal(canPurgeDeletionBarrier("complete", 100, 100), true);
});
