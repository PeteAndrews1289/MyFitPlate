const test = require("node:test");
const assert = require("node:assert/strict");
const { createMaiaChatCompletion } = require("../lib/maiaChatStreaming.js");

function fixture(events) {
  const controller = new AbortController();
  const chunks = [];
  let signal;
  const client = { chat: { completions: { create: async (params, options) => {
    signal = options?.signal;
    return (async function* () { for (const event of events) yield event; })();
  } } } };
  const response = { signal: controller.signal, sendChunk: async value => { chunks.push(value); return true; } };
  return { client, response, controller, chunks, get signal() { return signal; } };
}

test("streamed text is finalized only on stop, preserves identity and measured usage", async () => {
  const f = fixture([{ choices: [{ delta: { content: "Eat " } }] }, { choices: [{ delta: { content: "a meal." }, finish_reason: "stop" }] }, { choices: [], usage: { total_tokens: 14 } }]);
  const result = await createMaiaChatCompletion(f.client, { model: "unchanged" }, { stream: true, requestID: "request-one", response: f.response });
  assert.equal(result.choices[0].message.content, "Eat a meal.");
  assert.equal(result.usage.total_tokens, 14);
  assert.deepEqual(f.chunks.map(x => x.requestID), ["request-one", "request-one"]);
});

test("disconnect aborts provider and cannot produce a final accepted answer", async () => {
  const f = fixture([{ choices: [{ delta: { content: "Partial " } }] }, { choices: [{ delta: { content: "answer" }, finish_reason: "stop" }] }]);
  f.response.sendChunk = async () => false;
  await assert.rejects(createMaiaChatCompletion(f.client, {}, { stream: true, requestID: "one", response: f.response }), /disconnected/);
  assert.equal(f.signal.aborted, true);
});

test("callable abort signal cancels provider before the next token", async () => {
  const f = fixture([{ choices: [{ delta: { content: "Partial" } }] }, { choices: [{ delta: { content: "late" } }] }]);
  f.response.sendChunk = async () => { f.controller.abort(); return true; };
  await assert.rejects(createMaiaChatCompletion(f.client, {}, { stream: true, requestID: "one", response: f.response }), /cancelled/);
  assert.equal(f.signal.aborted, true);
});

test("truncated model output never becomes a completed result", async () => {
  const f = fixture([{ choices: [{ delta: { content: "Partial" }, finish_reason: "length" }] }]);
  await assert.rejects(createMaiaChatCompletion(f.client, {}, { stream: true, requestID: "one", response: f.response }), /incomplete/);
});

test("ordinary callers retain the existing completion request", async () => {
  let captured;
  const response = { choices: [{ message: { content: "Finished" }, finish_reason: "stop" }] };
  const client = { chat: { completions: { create: async params => { captured = params; return response; } } } };
  assert.equal(await createMaiaChatCompletion(client, { model: "same", messages: [] }, { stream: false, requestID: "one" }), response);
  assert.deepEqual(captured, { model: "same", messages: [] });
});
