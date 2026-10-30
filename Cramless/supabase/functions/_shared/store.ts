// What the functions need from the database, as one interface. Production uses PostgresStore (the RPCs in
// supabase/migrations/…_cramless_rpcs.sql, one transaction each); the tests use MemoryStore (tests/_memory_store.ts),
// which implements the same rules and runs the same contract suite (tests/store_contract.test.ts), against the
// local stack too when it's running.

import type { Plan } from "./contract.ts";
import type { Meter } from "./plans.ts";

export interface UserContext {
  /** False when the auth user has no profile: it was deleted. */
  exists: boolean;
  plan: Plan;
  expiresAt: string | null;
  timeZone: string;
  displayName: string;
}

export interface ConsumeResult {
  allowed: boolean;
  used: number;
}

export interface ScanResult extends ConsumeResult {
  /** True when this request opened a new scan (and cost one). */
  counted: boolean;
}

export type ScanKind = "transcribe" | "generate";

export interface AiRequestRow {
  userId: string;
  route: string;
  model: string;
  plan: Plan;
  status: number;
  mock: boolean;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  /** Decimal dollars, "0.000123450". */
  costUsd: string;
  latencyMs: number;
  /** When the request began (ISO 8601): the day's cost is summed from these. */
  createdAt: string;
}

export type Environment = "Production" | "Sandbox" | "Xcode";

export interface EntitlementRow {
  plan: "pro" | "squad" | "pass";
  productId: string;
  originalTransactionId: string;
  transactionId: string;
  purchaseDate: string;
  expiresAt: string | null;
  revokedAt: string | null;
  environment: Environment;
}

export interface NotificationUpdate {
  environment: Environment;
  originalTransactionId: string;
  transactionId: string | null;
  productId: string | null;
  plan: "pro" | "squad" | "pass" | null;
  purchaseDate: string;
  expiresAt: string | null;
  revokedAt: string | null;
}

export type InviteResult = { ok: true; squadId: string } | { ok: false; reason: "not_owner" | "full" | "code_taken" };

export type RedeemResult =
  | { ok: true; ownerName: string }
  | {
    ok: false;
    reason: "not_found" | "used" | "expired" | "own_squad" | "other_squad" | "owner_lapsed" | "full";
  };

export interface SquadMemberRow {
  id: string;
  name: string;
  joinedAt: string;
  isOwner: boolean;
}

export type MembersResult =
  | { ok: true; squadId: string; ownerId: string; members: SquadMemberRow[] }
  | { ok: false; reason: "no_squad" };

export type RemoveResult = { ok: true } | { ok: false; reason: "not_allowed" | "not_found" };

export const SQUAD_SEATS = 4;

export interface Store {
  context(userId: string, now: Date): Promise<UserContext>;
  consume(userId: string, meter: Meter, period: string, amount: number, limit: number | null): Promise<ConsumeResult>;
  refund(userId: string, meter: Meter, period: string, amount: number): Promise<void>;
  consumeScan(
    userId: string,
    kind: ScanKind,
    pages: number,
    period: string,
    limit: number | null,
    now: Date,
    windowMinutes: number,
    maxPages: number,
  ): Promise<ScanResult>;
  refundScan(userId: string, kind: ScanKind, pages: number, period: string, counted: boolean): Promise<void>;
  usage(userId: string, keys: { meter: Meter; period: string }[]): Promise<Partial<Record<Meter, number>>>;
  logRequest(row: AiRequestRow): Promise<void>;
  /** What the person's model calls have cost since `since`, in nano-dollars, from the request log (MOCK rows cost nothing). */
  spentSince(userId: string, since: Date): Promise<bigint>;
  saveEntitlements(userId: string, rows: EntitlementRow[], now: Date): Promise<void>;
  applyNotification(update: NotificationUpdate, now: Date): Promise<"applied" | "stale" | "unknown">;
  squadInvite(ownerId: string, code: string, expiresAt: Date, now: Date): Promise<InviteResult>;
  squadRedeem(userId: string, code: string, now: Date): Promise<RedeemResult>;
  squadMembers(userId: string): Promise<MembersResult>;
  squadRemove(actorId: string, memberId: string): Promise<RemoveResult>;
  deleteAiData(userId: string): Promise<void>;
  /** Every row, the person's storage folder and the auth user. */
  deleteAccount(userId: string): Promise<void>;
}
