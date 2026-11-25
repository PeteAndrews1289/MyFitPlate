const test = require("node:test");
const assert = require("node:assert/strict");
process.env.GCLOUD_PROJECT = "myfitplate-test-project";
const { deleteUserData, generateAIResponse } = require("../lib/index.js");
const { getFirestore } = require("firebase-admin/firestore");

// Fail immediately if a rejected callable reaches persistence. Never contacts a live project.
const db = getFirestore();
db.collection = () => { throw new Error("Unexpected database access before validation"); };

test("exported deletion callable rejects stale authentication before any persistence", async () => {
  await assert.rejects(deleteUserData.run({ data: {}, auth: { uid: "synthetic", token: { auth_time: 1 } } }),
    { code: "failed-precondition" });
  await assert.rejects(deleteUserData.run({ data: {} }), { code: "unauthenticated" });
});

test("exported deletion callable rejects a changed expected owner before persistence", async () => {
  await assert.rejects(deleteUserData.run({ data: { expectedUserID: "original-owner" },
    auth: { uid: "different-owner", token: { auth_time: Math.floor(Date.now() / 1000) } } }), { code: "permission-denied" });
});

test("exported AI callable rejects aggregate abuse before quota or provider work", async () => {
  await assert.rejects(generateAIResponse.run({
    auth: { uid: "synthetic", token: {} },
    data: { messages: Array(3).fill({ role: "user", content: "x".repeat(40000) }) },
  }), { code: "invalid-argument" });
});

test("exported AI callable enforces each budget cutoff before contacting OpenAI", async () => {
  const originalCollection = db.collection;
  const originalTransaction = db.runTransaction;
  try {
    for (const configuration of [
      { enabled: false }, { userDailyTokens: 0 }, { projectDailyTokens: 0 }, { callsPerMinute: 0 },
    ]) {
      const writes = [];
      db.collection = collection => ({ doc: id => ({ path: `${collection}/${id}` }) });
      db.runTransaction = async operation => operation({
        get: async ref => ({ exists: ref.path === "internalConfig/aiBudget", data: () =>
          ref.path === "internalConfig/aiBudget" ? configuration : undefined }),
        getAll: async (...refs) => refs.map(ref => ({ data: () =>
          ref.path === "internalConfig/aiBudget" ? configuration : undefined })),
        set: (ref, value) => writes.push({ path: ref.path, value }),
      });
      await assert.rejects(generateAIResponse.run({
        auth: { uid: "synthetic", token: {} },
        data: { messages: [{ role: "user", content: "Synthetic quota boundary check" }] },
      }), { code: configuration.enabled === false ? "unavailable" : "resource-exhausted" });
      assert.ok(writes.every(write => write.path.startsWith("aiUsage/")));
    }
  } finally {
    db.collection = originalCollection;
    db.runTransaction = originalTransaction;
  }
});
