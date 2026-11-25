import { HttpsError } from "firebase-functions/v2/https";

export const ACCOUNT_DELETION_BARRIERS = "accountDeletionBarriers";
export const COMPLETED_DELETION_RETENTION_MS = 48 * 60 * 60 * 1000;

/** Missing expected owner preserves the installed legacy client's API. New clients always send it. */
export function requireExpectedDeletionOwner(uid: string, expected: unknown): void {
  if (expected === undefined) return;
  if (typeof expected !== "string" || expected.length === 0) {
    throw new HttpsError("invalid-argument", "A valid expected account is required.");
  }
  if (expected !== uid) throw new HttpsError("permission-denied", "The active account changed. Nothing was deleted.");
}

/** Pending barriers never expire: removing one after partial failure would reopen client writes. */
export async function runDeletionWithBarrier(operations: {
  begin: () => Promise<unknown>;
  eraseData: () => Promise<unknown>;
  eraseAuth: () => Promise<unknown>;
  complete: () => Promise<unknown>;
}): Promise<void> {
  await operations.begin();
  await operations.eraseData();
  try { await operations.eraseAuth(); } catch (error) {
    if ((error as { code?: string })?.code !== "auth/user-not-found") throw error;
  }
  await operations.complete();
}

export function canPurgeDeletionBarrier(status: unknown, expiresAtMs: number | undefined, nowMs: number): boolean {
  return status === "complete" && expiresAtMs !== undefined && Number.isFinite(expiresAtMs) && expiresAtMs <= nowMs;
}
