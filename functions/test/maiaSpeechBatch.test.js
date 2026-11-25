const test = require("node:test");
const assert = require("node:assert/strict");
const { generateMaiaSpeechBatch, validateMaiaSpeechSegments, MAIA_SPEECH_MAX_BATCH_AUDIO_BYTES } = require("../lib/maiaSpeechBatch.js");
const { generateMaiaSpeechAudio } = require("../lib/maiaSpeech.js");
const { EventEmitter } = require("node:events");

for (const input of [[], Array(7).fill("Short."), [""], ["a".repeat(1801)], ["🙂".repeat(901)], [12]]) {
  test(`rejects invalid bounded speech input ${JSON.stringify(input).slice(0, 40)}`, () => assert.throws(() => validateMaiaSpeechSegments(input)));
}

test("batch preserves order, limits concurrency to three and shares a 6000 output-token budget", async () => {
  let active = 0, maximum = 0, outputBudget = 0;
  const measured = [];
  const result = await generateMaiaSpeechBatch("fake", ["First.", "Second longer.", "Third.", "Fourth.", "Fifth.", "Sixth."], "hash", {
    onSegment: async value => { measured.push(value); },
  }, async (text, limits) => {
    active++; maximum = Math.max(maximum, active); outputBudget += limits.maxOutputTokens;
    await new Promise(resolve => setTimeout(resolve, text === "First." ? 12 : 2));
    limits.onUsage({ inputTokens: 10, outputTokens: 20, totalTokens: 30 });
    active--; return Buffer.from(text);
  });
  assert.deepEqual(result.map(data => data.toString()), ["First.", "Second longer.", "Third.", "Fourth.", "Fifth.", "Sixth."]);
  assert.equal(maximum, 3); assert.ok(outputBudget <= 6000);
  assert.equal(measured.length, 6); assert.ok(measured.every(value => value.succeeded && value.usage.totalTokens === 30));
});

test("cancellation aborts in-flight segments and never starts queued ones", async () => {
  const controller = new AbortController(); let started = 0, stopped = 0;
  const promise = generateMaiaSpeechBatch("fake", ["1", "2", "3", "4", "5", "6"], "hash", { signal: controller.signal }, async (_, limits) => {
    started++;
    return new Promise((resolve, reject) => limits.signal.addEventListener("abort", () => { stopped++; reject(new Error("cancelled")); }, { once: true }));
  });
  controller.abort(); await assert.rejects(promise, /cancelled/);
  assert.equal(started, 3); assert.equal(stopped, 3);
});

test("overall timeout cancels all workers even while they await a segment", async () => {
  await assert.rejects(generateMaiaSpeechBatch("fake", ["One", "Two"], "hash", { timeoutMs: 5 }, async (_, limits) =>
    new Promise((resolve, reject) => limits.signal.addEventListener("abort", () => reject(new Error("timed out")), { once: true }))), /timed out/);
});

test("aggregate encoded-audio bound rejects a batch before it can be returned", async () => {
  await assert.rejects(generateMaiaSpeechBatch("fake", ["One", "Two"], "hash", {}, async () =>
    Buffer.alloc(MAIA_SPEECH_MAX_BATCH_AUDIO_BYTES / 2 + 1)), /too large/);
});

test("provider segment abort closes websocket and reports measured usage without fabrication", async () => {
  class Socket extends EventEmitter { send() {} close() { this.closed = true; } terminate() { this.closed = true; } }
  const socket = new Socket(); const controller = new AbortController(); const usages = [];
  const promise = generateMaiaSpeechAudio("fake", "One", "hash", () => socket, 1000, { signal: controller.signal, onUsage: value => usages.push(value) });
  controller.abort(); await assert.rejects(promise, /cancelled/); assert.equal(socket.closed, true); assert.deepEqual(usages, []);
});
