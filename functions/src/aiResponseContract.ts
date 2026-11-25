import {randomUUID} from "node:crypto";
import {AIRequestKind, AIRequestRoute} from "./aiRequestRouting";

export const AI_SERVER_POLICY_VERSION = "myfitplate-ai-policy-2026-11-04-v1";
export const AI_RESPONSE_ENVELOPE_VERSION = 1;

export interface AIResponseMetadata {
  envelopeVersion: number;
  requestID: string;
  requestKind: AIRequestKind;
  contractVersion: string;
  serverPolicyVersion: string;
  model: string;
  fallbackUsed: boolean;
  generatedAt: string;
  durationMs: number;
  finishReason: "stop";
}

/** Request identity is correlation metadata, never authorization or a mutation receipt. */
export function aiResponseRequestID(value: unknown): string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value.toLowerCase() : randomUUID();
}

export function aiResponseContractVersion(route: AIRequestRoute, responseFormat?: unknown): string {
  const forced = route.forcedResponseFormat as {json_schema?: {name?: string}} | undefined;
  if (forced?.json_schema?.name) return `${forced.json_schema.name}-v1`;
  const format = responseFormat as {type?: string} | undefined;
  // Client-specific action/recipe validators still own semantic interpretation.
  return `${route.kind}-${format?.type === "json_object" ? "json-object" : "text"}-v1`;
}

export function makeAIResponseMetadata(input: {
  requestID: string; route: AIRequestRoute; responseFormat?: unknown; model: string;
  configuredPrimaryModel: string; startedAt: number; now?: number;
}): AIResponseMetadata {
  const now = input.now ?? Date.now();
  return {
    envelopeVersion: AI_RESPONSE_ENVELOPE_VERSION,
    requestID: aiResponseRequestID(input.requestID), requestKind: input.route.kind,
    contractVersion: aiResponseContractVersion(input.route, input.responseFormat),
    serverPolicyVersion: AI_SERVER_POLICY_VERSION, model: input.model,
    fallbackUsed: input.model !== input.configuredPrimaryModel,
    generatedAt: new Date(now).toISOString(), durationMs: Math.max(0, Math.round(now - input.startedAt)),
    finishReason: "stop",
  };
}
