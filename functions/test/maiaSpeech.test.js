const test = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const { MAIA_SPEECH_MODEL, buildMaiaSpeechRequest, generateMaiaSpeechAudio } = require("../lib/maiaSpeech.js");

class FakeSocket extends EventEmitter {
  sent = [];
  closed = false;
  send(data) { this.sent.push(JSON.parse(data)); }
  close() { this.closed = true; }
  terminate() { this.closed = true; }
  event(value) { this.emit("message", Buffer.from(JSON.stringify(value))); }
}

test("speech waits for configured session and packages completed PCM as playable WAV", async () => {
  const socket = new FakeSocket();
  const audio = generateMaiaSpeechAudio("fake", "Eat 25 grams of protein.", "user-hash", () => socket);
  socket.emit("open");
  assert.equal(socket.sent[0].session.model, "gpt-realtime-2.1");
  assert.equal(socket.sent.length, 1);
  socket.event({ type: "session.updated" });
  assert.equal(socket.sent[1].item.content[0].text, "Eat 25 grams of protein.");
  assert.equal(socket.sent[2].type, "response.create");
  socket.event({ type: "response.output_audio.delta", delta: Buffer.from([0, 1, 2, 3]).toString("base64") });
  socket.event({ type: "response.done", response: { status: "completed" } });
  const wav = await audio;
  assert.equal(wav.toString("ascii", 0, 4), "RIFF");
  assert.equal(wav.readUInt32LE(24), 24000);
  assert.equal(wav.readUInt32LE(40), 4);
  assert.equal(socket.closed, true);
});

for (const event of [
  { type: "error" },
  { type: "response.done", response: { status: "incomplete" } },
  { type: "response.done", response: { status: "completed" } },
]) test(`rejects failed, truncated or empty speech: ${JSON.stringify(event)}`, async () => {
  const socket = new FakeSocket();
  const result = generateMaiaSpeechAudio("fake", "Hello", "user", () => socket);
  socket.event(event);
  await assert.rejects(result);
  assert.equal(socket.closed, true);
});

test("speech timeout closes connection and allows native fallback", async () => {
  const socket = new FakeSocket();
  await assert.rejects(generateMaiaSpeechAudio("fake", "Hello", "user", () => socket, 5), /timed out/);
  assert.equal(socket.closed, true);
});

test("speech preserves read-aloud instructions and bounded output", () => {
  const request = buildMaiaSpeechRequest("A practical next step.");
  assert.equal(MAIA_SPEECH_MODEL, "gpt-realtime-2.1");
  assert.equal(request.session.session.audio.output.voice, "marin");
  assert.match(request.session.session.instructions, /exactly/);
  assert.equal(request.session.session.max_output_tokens, 6000);
});
