const test = require("node:test");
const assert = require("node:assert/strict");
const { requireRecentAuthentication, aiInputAllowance, aiBudgetLimit } = require("../lib/requestGuards.js");

test("deletion rejects stale, missing, malformed and future authentication", () => {
  const now = 1000000;
  for (const value of [undefined, "999", NaN, 699, 1031]) {
    assert.throws(() => requireRecentAuthentication(value, now), { code: "failed-precondition" });
  }
  assert.doesNotThrow(() => requireRecentAuthentication(995, now));
});

test("aggregate input limits cover all messages, UTF-8 bytes and image count", () => {
  assert.throws(() => aiInputAllowance(Array(3).fill({ content: "x".repeat(40000) })), { code: "invalid-argument" });
  assert.throws(() => aiInputAllowance([{ content: "界".repeat(40000) }]), { code: "invalid-argument" });
  assert.throws(() => aiInputAllowance([{ content: Array(3).fill({ type: "image_url" }) }]), { code: "invalid-argument" });
  assert.equal(aiInputAllowance([{ content: [{ type: "text", text: "meal" }, { type: "image_url" }] }]), 16004);
});

test("zero budget is a cutoff and invalid configuration cannot disable limits", () => {
  assert.equal(aiBudgetLimit(0, 100), 0);
  for (const value of [NaN, Infinity, -1, "unlimited"]) assert.equal(aiBudgetLimit(value, 100), 100);
});
