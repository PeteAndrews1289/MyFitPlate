/** The existing coaching route can stream text while retaining one finalized response contract. */
export interface MaiaCompletionClient {
  chat: { completions: { create(params: any, options?: { signal?: AbortSignal }): Promise<any> } };
}
export interface MaiaStreamResponse {
  signal: AbortSignal;
  sendChunk(chunk: { requestID: string; delta: string }): Promise<boolean>;
}

export async function createMaiaChatCompletion(
  client: MaiaCompletionClient,
  params: any,
  options: { stream: boolean; requestID: string; response?: MaiaStreamResponse },
): Promise<any> {
  const signal = options.response?.signal;
  if (signal?.aborted) throw new Error("AI request cancelled");
  if (!options.stream || !options.response) {
    return client.chat.completions.create(params, signal ? { signal } : undefined);
  }
  const controller = new AbortController();
  const abort = () => controller.abort();
  signal?.addEventListener("abort", abort, { once: true });
  try {
    const stream = await client.chat.completions.create(
      { ...params, stream: true, stream_options: { include_usage: true } }, { signal: controller.signal },
    );
    let content = "";
    let finishReason: string | null = null;
    let usage: any;
    for await (const event of stream) {
      if (signal?.aborted || controller.signal.aborted) throw new Error("AI request cancelled");
      if (event.usage) usage = event.usage;
      const choice = event.choices?.[0];
      if (choice?.finish_reason) finishReason = choice.finish_reason;
      const delta = choice?.delta?.content;
      if (typeof delta === "string" && delta.length > 0) {
        content += delta;
        // Firebase waits for the write callback, but can return false when Node buffered
        // a successfully delivered chunk. The callable's abort signal tracks disconnects.
        const wroteImmediately = await options.response.sendChunk({ requestID: options.requestID, delta });
        if (!wroteImmediately && controller.signal.aborted) throw new Error("AI client disconnected");
      }
    }
    if (controller.signal.aborted) throw new Error("AI request cancelled");
    if (finishReason !== "stop" || !content.trim()) throw new Error("AI response was incomplete or empty");
    return { choices: [{ finish_reason: finishReason, message: { content } }], usage };
  } finally {
    signal?.removeEventListener("abort", abort);
    controller.abort();
  }
}
