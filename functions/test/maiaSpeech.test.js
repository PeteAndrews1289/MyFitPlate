const test = require("node:test");
const assert = require("node:assert/strict");

const {
  MAIA_SPEECH_INSTRUCTIONS,
  MAIA_SPEECH_MAX_CHARACTERS,
  MAIA_SPEECH_MODEL,
  MAIA_SPEECH_VOICE,
  buildMaiaSpeechRequest,
} = require("../lib/maiaSpeech.js");

test("Maia natural speech uses a model that supports the selected voice", () => {
  const request = buildMaiaSpeechRequest("A practical next step.");

  assert.equal(MAIA_SPEECH_MODEL, "gpt-4o-mini-tts");
  assert.equal(MAIA_SPEECH_VOICE, "marin");
  assert.equal(request.model, MAIA_SPEECH_MODEL);
  assert.equal(request.voice, MAIA_SPEECH_VOICE);
  assert.equal(request.response_format, "mp3");
  assert.match(request.instructions, /subtle French lilt/);
});

test("Maia natural speech keeps its bounded server contract", () => {
  assert.equal(MAIA_SPEECH_MAX_CHARACTERS, 1_800);
  assert.equal(MAIA_SPEECH_INSTRUCTIONS.includes("theatricality"), true);
});
