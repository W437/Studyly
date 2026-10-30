// The Store on Supabase: every call is one RPC (supabase/migrations/…_cramless_rpcs.sql) made with the service
// role, plus the Storage and Auth admin APIs for account deletion. Database errors become a bare 500.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Plan } from "./contract.ts";
import { ApiError } from "./errors.ts";
import { isoDate } from "./http.ts";
import type { Meter } from "./plans.ts";
import type {
  AiRequestRow,
  ConsumeResult,
  EntitlementRow,
  InviteResult,
  MembersResult,
  NotificationUpdate,
  RedeemResult,
  RemoveResult,
  ScanKind,
  ScanResult,
  Store,
  UserContext,
} from "./store.ts";

export type Admin = SupabaseClient;

export function createAdmin(url: string, serviceKey: string, fetchImpl?: typeof fetch): Admin {
  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { headers: { "X-Client-Info": "cramless-functions" }, ...(fetchImpl ? { fetch: fetchImpl } : {}) },
  });
}

function dbError(fn: string, code?: string): ApiError {
  return new ApiError("upstream", `Database call ${fn} failed${code ? ` (${code})` : ""}.`, {}, 500);
}

// deno-lint-ignore no-explicit-any
type Json = any;

export class PostgresStore implements Store {
  constructor(private readonly admin: Admin, private readonly bucket = "sources") {}

  async #rpc(fn: string, args: Record<string, unknown>): Promise<Json> {
    const { data, error } = await this.admin.rpc(fn, args);
    if (error) throw dbError(fn, error.code);
    return data;
  }

  async context(userId: string, now: Date): Promise<UserContext> {
    const r = await this.#rpc("cramless_context", { p_user: userId, p_now: now.toISOString() });
    if (!r?.exists) return { exists: false, plan: "free", expiresAt: null, timeZone: "UTC", displayName: "" };
    return {
      exists: true,
      plan: (r.plan ?? "free") as Plan,
      expiresAt: isoDate(r.expires_at),
      timeZone: r.timezone ?? "UTC",
      displayName: r.display_name ?? "",
    };
  }

  async consume(userId: string, meter: Meter, period: string, amount: number, limit: number | null) {
    const r = await this.#rpc("cramless_consume", {
      p_user: userId,
      p_meter: meter,
      p_period: period,
      p_amount: amount,
      p_limit: limit,
    });
    return { allowed: r?.allowed === true, used: Number(r?.used ?? 0) } satisfies ConsumeResult;
  }

  async refund(userId: string, meter: Meter, period: string, amount: number): Promise<void> {
    await this.#rpc("cramless_refund", { p_user: userId, p_meter: meter, p_period: period, p_amount: amount });
  }

  async consumeScan(
    userId: string,
    kind: ScanKind,
    pages: number,
    period: string,
    limit: number | null,
    now: Date,
    windowMinutes: number,
    maxPages: number,
  ): Promise<ScanResult> {
    const r = await this.#rpc("cramless_consume_scan", {
      p_user: userId,
      p_kind: kind,
      p_pages: pages,
      p_period: period,
      p_limit: limit,
      p_now: now.toISOString(),
      p_window_minutes: windowMinutes,
      p_max_pages: maxPages,
    });
    return { allowed: r?.allowed === true, used: Number(r?.used ?? 0), counted: r?.counted === true };
  }

  async refundScan(userId: string, kind: ScanKind, pages: number, period: string, counted: boolean): Promise<void> {
    await this.#rpc("cramless_refund_scan", {
      p_user: userId,
      p_kind: kind,
      p_pages: pages,
      p_period: period,
      p_counted: counted,
    });
  }

  async usage(userId: string, keys: { meter: Meter; period: string }[]): Promise<Partial<Record<Meter, number>>> {
    const r = await this.#rpc("cramless_usage", { p_user: userId, p_keys: keys });
    const out: Partial<Record<Meter, number>> = {};
    for (const { meter } of keys) out[meter] = Number(r?.[meter] ?? 0);
    return out;
  }

  async logRequest(row: AiRequestRow): Promise<void> {
    const { error } = await this.admin.from("ai_requests").insert({
      user_id: row.userId,
      route: row.route,
      model: row.model,
      plan: row.plan,
      status: row.status,
      mock: row.mock,
      input_tokens: row.inputTokens,
      output_tokens: row.outputTokens,
      cache_read_tokens: row.cacheReadTokens,
      cache_write_tokens: row.cacheWriteTokens,
      cost_usd: row.costUsd,
      latency_ms: row.latencyMs,
      created_at: row.createdAt,
    });
    if (error) throw dbError("ai_requests", error.code);
  }

  async spentSince(userId: string, since: Date): Promise<bigint> {
    const r = await this.#rpc("cramless_spent_since", { p_user: userId, p_since: since.toISOString() });
    const nano = Number(r ?? 0);
    return Number.isFinite(nano) && nano > 0 ? BigInt(Math.floor(nano)) : 0n;
  }

  async saveEntitlements(userId: string, rows: EntitlementRow[], now: Date): Promise<void> {
    if (rows.length === 0) return;
    await this.#rpc("cramless_save_entitlements", {
      p_user: userId,
      p_rows: rows.map((r) => ({
        plan: r.plan,
        product_id: r.productId,
        original_transaction_id: r.originalTransactionId,
        transaction_id: r.transactionId,
        purchase_date: r.purchaseDate,
        expires_at: r.expiresAt,
        revoked_at: r.revokedAt,
        environment: r.environment,
      })),
      p_now: now.toISOString(),
    });
  }

  async applyNotification(u: NotificationUpdate, now: Date): Promise<"applied" | "stale" | "unknown"> {
    const r = await this.#rpc("cramless_apply_notification", {
      p_environment: u.environment,
      p_original: u.originalTransactionId,
      p_transaction: u.transactionId,
      p_product: u.productId,
      p_plan: u.plan,
      p_purchase: u.purchaseDate,
      p_expires: u.expiresAt,
      p_revoked: u.revokedAt,
      p_now: now.toISOString(),
    });
    return r === "applied" || r === "stale" ? r : "unknown";
  }

  async squadInvite(ownerId: string, code: string, expiresAt: Date, now: Date): Promise<InviteResult> {
    const { data, error } = await this.admin.rpc("cramless_squad_invite", {
      p_owner: ownerId,
      p_code: code,
      p_expires: expiresAt.toISOString(),
      p_now: now.toISOString(),
    });
    if (error?.code === "23505") return { ok: false, reason: "code_taken" };
    if (error) throw dbError("cramless_squad_invite", error.code);
    return data?.ok ? { ok: true, squadId: String(data.squad_id) } : { ok: false, reason: data?.reason ?? "not_owner" };
  }

  async squadRedeem(userId: string, code: string, now: Date): Promise<RedeemResult> {
    const r = await this.#rpc("cramless_squad_redeem", { p_user: userId, p_code: code, p_now: now.toISOString() });
    return r?.ok
      ? { ok: true, ownerName: String(r.owner_name ?? "") }
      : { ok: false, reason: r?.reason ?? "not_found" };
  }

  async squadMembers(userId: string): Promise<MembersResult> {
    const r = await this.#rpc("cramless_squad_members", { p_user: userId });
    if (!r?.ok) return { ok: false, reason: "no_squad" };
    return {
      ok: true,
      squadId: String(r.squad_id),
      ownerId: String(r.owner_id),
      members: (r.members ?? []).map((m: Json) => ({
        id: String(m.id),
        name: String(m.name ?? ""),
        joinedAt: isoDate(m.joined_at) ?? isoDate(new Date())!,
        isOwner: m.is_owner === true,
      })),
    };
  }

  async squadRemove(actorId: string, memberId: string): Promise<RemoveResult> {
    const r = await this.#rpc("cramless_squad_remove", { p_actor: actorId, p_member: memberId });
    return r?.ok ? { ok: true } : { ok: false, reason: r?.reason ?? "not_found" };
  }

  async deleteAiData(userId: string): Promise<void> {
    await this.#rpc("cramless_delete_ai_data", { p_user: userId });
  }

  async deleteAccount(userId: string): Promise<void> {
    await this.#removeFolder(userId);
    await this.#rpc("cramless_delete_account_data", { p_user: userId });
    const { error } = await this.admin.auth.admin.deleteUser(userId);
    if (error && error.status !== 404) throw dbError("auth.deleteUser", String(error.status ?? ""));
  }

  /** Removes `<userId>/…` from the bucket: source folders, then their files (two levels, as the app writes). */
  async #removeFolder(userId: string): Promise<void> {
    const storage = this.admin.storage.from(this.bucket);
    const files: string[] = [];
    const walk = async (prefix: string, depth: number) => {
      for (let offset = 0;; offset += 1000) {
        const { data, error } = await storage.list(prefix, { limit: 1000, offset });
        if (error) throw dbError("storage.list");
        for (const entry of data ?? []) {
          const path = `${prefix}/${entry.name}`;
          if (entry.id === null && depth < 3) await walk(path, depth + 1);
          else files.push(path);
        }
        if (!data || data.length < 1000) break;
      }
    };
    await walk(userId, 1);
    for (let i = 0; i < files.length; i += 500) {
      const { error } = await storage.remove(files.slice(i, i + 500));
      if (error) throw dbError("storage.remove");
    }
  }
}
