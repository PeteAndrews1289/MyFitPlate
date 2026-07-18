export const MAIA_SPEECH_MODEL = "gpt-4o-mini-tts";
export const MAIA_SPEECH_VOICE = "marin";
export const MAIA_SPEECH_MAX_CHARACTERS = 1_800;
export const MAIA_SPEECH_INSTRUCTIONS = [
  "Speak naturally and conversationally with warm, calm confidence.",
  "Use clear American English with a subtle French lilt, gentle phrasing,",
  "and varied but restrained intonation.",
  "Avoid theatricality, canned enthusiasm, or announcing formatting.",
].join(" ");

export function buildMaiaSpeechRequest(text: string) {
  return {
    model: MAIA_SPEECH_MODEL,
    voice: MAIA_SPEECH_VOICE,
    input: text,
    instructions: MAIA_SPEECH_INSTRUCTIONS,
    response_format: "mp3" as const,
    speed: 0.96,
  };
}
