import { generateMaiaSpeechAudio, MAIA_SPEECH_MAX_CHARACTERS, MaiaSpeechUsage } from "./maiaSpeech";

export const MAIA_SPEECH_MAX_SEGMENTS = 6;
export const MAIA_SPEECH_MAX_BATCH_AUDIO_BYTES = 6 * 1024 * 1024;
export interface MaiaSpeechSegmentResult { index: number; characters: number; durationMs: number; succeeded: boolean; usage?: MaiaSpeechUsage; }
export type MaiaSpeechSegmentGenerator = (text: string, options: {
  signal: AbortSignal; maxOutputTokens: number; timeoutMs: number; onUsage: (usage: MaiaSpeechUsage) => void;
}) => Promise<Buffer>;

export function validateMaiaSpeechSegments(value: unknown): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAIA_SPEECH_MAX_SEGMENTS ||
      value.some(text => typeof text !== "string" || !text.trim())) throw new Error("Invalid speech sentence batch");
  const texts = value.map(text => (text as string).trim());
  if (texts.join(" ").length > MAIA_SPEECH_MAX_CHARACTERS) throw new Error("Speech batch exceeds 1800 characters");
  return texts;
}

/** A bounded batch retains original order, never reserves six full-response output budgets. */
export async function generateMaiaSpeechBatch(
  apiKey: string, texts: string[], safetyIdentifier: string,
  options: { signal?: AbortSignal; timeoutMs?: number; onSegment?: (result: MaiaSpeechSegmentResult) => Promise<void> } = {},
  generator: MaiaSpeechSegmentGenerator = (text, limits) => generateMaiaSpeechAudio(apiKey, text, safetyIdentifier,
    undefined, limits.timeoutMs, { signal: limits.signal, maxOutputTokens: limits.maxOutputTokens,
      maximumAudioBytes: MAIA_SPEECH_MAX_BATCH_AUDIO_BYTES, onUsage: limits.onUsage }),
): Promise<Buffer[]> {
  const sentences = validateMaiaSpeechSegments(texts);
  const controller = new AbortController();
  const abort = () => controller.abort();
  options.signal?.addEventListener("abort", abort, { once: true });
  if (options.signal?.aborted) controller.abort();
  const deadline = Date.now() + Math.min(25_000, Math.max(1, options.timeoutMs ?? 25_000));
  const timeout = setTimeout(abort, Math.max(1, deadline - Date.now()));
  const totalCharacters = sentences.reduce((sum, text) => sum + text.length, 0);
  const remainingOutputTokens = 6_000 - 256 * sentences.length;
  const outputs: Buffer[] = new Array(sentences.length);
  let next = 0;
  let totalBytes = 0;
  const work = async () => {
    while (next < sentences.length) {
      if (controller.signal.aborted) throw new Error("Speech batch cancelled or timed out");
      const index = next++;
      const started = Date.now();
      const text = sentences[index];
      let usage: MaiaSpeechUsage | undefined;
      let succeeded = false;
      try {
        const audio = await generator(text, { signal: controller.signal,
          maxOutputTokens: 256 + Math.floor(remainingOutputTokens * text.length / totalCharacters),
          timeoutMs: Math.max(1, deadline - Date.now()), onUsage: value => { usage = value; } });
        if (controller.signal.aborted) throw new Error("Speech batch cancelled or timed out");
        totalBytes += audio.length;
        if (!audio.length || totalBytes > MAIA_SPEECH_MAX_BATCH_AUDIO_BYTES) throw new Error("Speech batch output too large");
        outputs[index] = audio; succeeded = true;
      } catch (error) {
        controller.abort(); throw error;
      } finally {
        await options.onSegment?.({ index, characters: text.length, durationMs: Date.now() - started, succeeded, usage });
      }
    }
  };
  try {
    const errors: unknown[] = [];
    await Promise.all(Array.from({ length: Math.min(3, sentences.length) }, () => work().catch(error => { errors.push(error); })));
    if (errors.length) throw errors[0];
    return outputs;
  } finally {
    clearTimeout(timeout); options.signal?.removeEventListener("abort", abort); controller.abort();
  }
}
