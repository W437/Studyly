// The Store in memory, for tests: the same rules as the SQL functions in supabase/migrations/…_cramless_rpcs.sql,
// statement for statement. tests/store_contract.test.ts runs one suite against this and, when the local stack is
// up, against PostgresStore, so the two can't drift.

import type { Plan } from "../_shared/contract.ts";
import type { Meter } from "../_shared/plans.ts";
import {
  type AiRequestRow,
  type ConsumeResult,
  type EntitlementRow,
  type InviteResult,
  type MembersResult,
  type NotificationUpdate,
  type RedeemResult,
  type RemoveResult,
  type ScanKind,
  type ScanResult,
  SQUAD_SEATS,
  type Store,
  type UserContext,
} from "../_shared/store.ts";

interface Entitlement extends EntitlementRow {
  userId: string;
}

interface ScanWindow {
  openedAt: number;
  period: string | null;
  pages: number;
  generated: boolean;
}

const RANK: Record<string, number> = { squad: 3, pro: 2, pass: 1 };
const iso = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");

export class MemoryStore implements Store {
  readonly profiles = new Map<string, { displayName: string; timeZone: string }>();
  readonly entitlements: Entitlement[] = [];
  readonly counters = new Map<string, number>();
  readonly windows = new Map<string, ScanWindow>();
  readonly squads = new Map<string, { id: string; ownerId: string; createdAt: number }>();
  readonly members: { squadId: string; userId: string; joinedAt: number }[] = [];
  readonly invites = new Map<
    string,
    { code: string; squadId: string; createdAt: number; expiresAt: number; redeemedBy?: string; redeemedAt?: number }
  >();
  readonly requests: AiRequestRow[] = [];
  /** Users whose deleteAccount ran. */
  readonly deleted = new Set<string>();
  #nextSquad = 1;

  addUser(id: string, displayName = "", timeZone = "UTC"): string {
    this.profiles.set(id, { displayName, timeZone });
    return id;
  }

  // ---- Plans ----

  #active(e: Entitlement, now: number): boolean {
    return e.revokedAt === null && (e.expiresAt === null || Date.parse(e.expiresAt) > now);
  }

  #ownerActive(ownerId: string, now: number): boolean {
    return this.entitlements.some((e) => e.userId === ownerId && e.plan === "squad" && this.#active(e, now));
  }

  #planOf(userId: string, now: number): { plan: Plan; expiresAt: string | null } | null {
    const candidates: { plan: string; expiresAt: string | null }[] = [];
    for (const e of this.entitlements) {
      if (e.userId === userId && this.#active(e, now)) candidates.push({ plan: e.plan, expiresAt: e.expiresAt });
    }
    for (const m of this.members.filter((m) => m.userId === userId)) {
      const squad = this.squads.get(m.squadId);
      if (!squad) continue;
      for (const e of this.entitlements) {
        if (e.userId === squad.ownerId && e.plan === "squad" && this.#active(e, now)) {
          candidates.push({ plan: "squad", expiresAt: e.expiresAt });
        }
      }
    }
    candidates.sort((a, b) =>
      (RANK[b.plan] ?? 0) - (RANK[a.plan] ?? 0) ||
      (a.expiresAt === null ? -1 : b.expiresAt === null ? 1 : Date.parse(b.expiresAt) - Date.parse(a.expiresAt))
    );
    return candidates[0] ? { plan: candidates[0].plan as Plan, expiresAt: candidates[0].expiresAt } : null;
  }

  context(userId: string, now: Date): Promise<UserContext> {
    const profile = this.profiles.get(userId);
    if (!profile) {
      return Promise.resolve({ exists: false, plan: "free", expiresAt: null, timeZone: "UTC", displayName: "" });
    }
    const plan = this.#planOf(userId, now.getTime());
    return Promise.resolve({
      exists: true,
      plan: plan?.plan ?? "free",
      expiresAt: plan?.expiresAt ?? null,
      timeZone: profile.timeZone,
      displayName: profile.displayName,
    });
  }

  // ---- Quotas ----

  #key(userId: string, meter: Meter, period: string) {
    return `${userId}|${meter}|${period}`;
  }

  used(userId: string, meter: Meter, period: string): number {
    return this.counters.get(this.#key(userId, meter, period)) ?? 0;
  }

  #consume(userId: string, meter: Meter, period: string, amount: number, limit: number | null): ConsumeResult {
    const used = this.used(userId, meter, period);
    if (limit !== null && used + amount > limit) return { allowed: false, used };
    this.counters.set(this.#key(userId, meter, period), used + amount);
    return { allowed: true, used: used + amount };
  }

  consume(userId: string, meter: Meter, period: string, amount: number, limit: number | null) {
    return Promise.resolve(this.#consume(userId, meter, period, amount, limit));
  }

  refund(userId: string, meter: Meter, period: string, amount: number): Promise<void> {
    const key = this.#key(userId, meter, period);
    if (this.counters.has(key)) this.counters.set(key, Math.max(0, this.counters.get(key)! - amount));
    return Promise.resolve();
  }

  consumeScan(
    userId: string,
    kind: ScanKind,
    pages: number,
    period: string,
    limit: number | null,
    now: Date,
    windowMinutes: number,
    maxPages: number,
  ): Promise<ScanResult> {
    const w = this.windows.get(userId) ?? { openedAt: -Infinity, period: null, pages: 0, generated: true };
    const open = w.openedAt > now.getTime() - windowMinutes * 60_000 && !w.generated && w.period === period &&
      (kind === "generate" || w.pages + pages <= maxPages);
    if (open) {
      this.windows.set(userId, {
        ...w,
        pages: w.pages + (kind === "transcribe" ? pages : 0),
        generated: kind === "generate",
      });
      return Promise.resolve({ allowed: true, used: this.used(userId, "scans", period), counted: false });
    }
    const r = this.#consume(userId, "scans", period, 1, limit);
    if (r.allowed) {
      this.windows.set(userId, { openedAt: now.getTime(), period, pages, generated: kind === "generate" });
    } else if (!this.windows.has(userId)) {
      this.windows.set(userId, w);
    }
    return Promise.resolve({ ...r, counted: r.allowed });
  }

  refundScan(userId: string, kind: ScanKind, pages: number, period: string, counted: boolean): Promise<void> {
    const w = this.windows.get(userId);
    if (counted) {
      const key = this.#key(userId, "scans", period);
      if (this.counters.has(key)) this.counters.set(key, Math.max(0, this.counters.get(key)! - 1));
      if (w) this.windows.set(userId, { ...w, openedAt: -Infinity, pages: 0, generated: true });
    } else if (w && kind === "generate") {
      this.windows.set(userId, { ...w, generated: false });
    } else if (w) {
      this.windows.set(userId, { ...w, pages: Math.max(0, w.pages - pages) });
    }
    return Promise.resolve();
  }

  usage(userId: string, keys: { meter: Meter; period: string }[]): Promise<Partial<Record<Meter, number>>> {
    const out: Partial<Record<Meter, number>> = {};
    for (const { meter, period } of keys) out[meter] = this.used(userId, meter, period);
    return Promise.resolve(out);
  }

  logRequest(row: AiRequestRow): Promise<void> {
    this.requests.push(row);
    return Promise.resolve();
  }

  // ---- Entitlements ----

  saveEntitlements(userId: string, rows: EntitlementRow[], _now: Date): Promise<void> {
    for (const r of rows) {
      const existing = this.entitlements.find((e) =>
        e.environment === r.environment && e.originalTransactionId === r.originalTransactionId
      );
      if (!existing) {
        this.entitlements.push({ ...r, userId });
        continue;
      }
      existing.userId = userId;
      if (Date.parse(r.purchaseDate) >= Date.parse(existing.purchaseDate)) {
        Object.assign(existing, { ...r, userId });
      }
    }
    return Promise.resolve();
  }

  applyNotification(u: NotificationUpdate, _now: Date): Promise<"applied" | "stale" | "unknown"> {
    const row = this.entitlements.find((e) =>
      e.environment === u.environment && e.originalTransactionId === u.originalTransactionId
    );
    if (!row) return Promise.resolve("unknown");
    if (Date.parse(u.purchaseDate) < Date.parse(row.purchaseDate)) return Promise.resolve("stale");
    row.plan = u.plan ?? row.plan;
    row.productId = u.productId ?? row.productId;
    row.transactionId = u.transactionId ?? row.transactionId;
    row.purchaseDate = u.purchaseDate;
    row.expiresAt = u.expiresAt;
    row.revokedAt = u.revokedAt;
    return Promise.resolve("applied");
  }

  // ---- Squad ----

  #squadMembers(squadId: string) {
    return this.members.filter((m) => m.squadId === squadId);
  }

  squadInvite(ownerId: string, code: string, expiresAt: Date, now: Date): Promise<InviteResult> {
    if (!this.#ownerActive(ownerId, now.getTime())) return Promise.resolve({ ok: false, reason: "not_owner" });
    let squad = [...this.squads.values()].find((s) => s.ownerId === ownerId);
    if (!squad) {
      squad = { id: `squad-${this.#nextSquad++}`, ownerId, createdAt: now.getTime() };
      this.squads.set(squad.id, squad);
    }
    if (this.#squadMembers(squad.id).length + 1 >= SQUAD_SEATS) return Promise.resolve({ ok: false, reason: "full" });
    if (this.invites.has(code)) return Promise.resolve({ ok: false, reason: "code_taken" });
    this.invites.set(code, { code, squadId: squad.id, createdAt: now.getTime(), expiresAt: expiresAt.getTime() });
    return Promise.resolve({ ok: true, squadId: squad.id });
  }

  squadRedeem(userId: string, code: string, now: Date): Promise<RedeemResult> {
    const invite = this.invites.get(code.trim().toUpperCase());
    if (!invite) return Promise.resolve({ ok: false, reason: "not_found" });
    const squad = this.squads.get(invite.squadId)!;
    const ownerName = this.profiles.get(squad.ownerId)?.displayName.trim() || "Your friend";
    const current = this.members.find((m) => m.userId === userId)?.squadId;
    if (current === squad.id) return Promise.resolve({ ok: true, ownerName });
    if (invite.redeemedAt !== undefined) return Promise.resolve({ ok: false, reason: "used" });
    if (invite.expiresAt <= now.getTime()) return Promise.resolve({ ok: false, reason: "expired" });
    if (squad.ownerId === userId) return Promise.resolve({ ok: false, reason: "own_squad" });
    if (current !== undefined) return Promise.resolve({ ok: false, reason: "other_squad" });
    if (!this.#ownerActive(squad.ownerId, now.getTime())) return Promise.resolve({ ok: false, reason: "owner_lapsed" });
    if (this.#squadMembers(squad.id).length + 1 >= SQUAD_SEATS) return Promise.resolve({ ok: false, reason: "full" });
    this.members.push({ squadId: squad.id, userId, joinedAt: now.getTime() });
    invite.redeemedBy = userId;
    invite.redeemedAt = now.getTime();
    return Promise.resolve({ ok: true, ownerName });
  }

  squadMembers(userId: string): Promise<MembersResult> {
    let squad = [...this.squads.values()].find((s) => s.ownerId === userId);
    if (!squad) {
      const membership = this.members.find((m) => m.userId === userId);
      squad = membership ? this.squads.get(membership.squadId) : undefined;
    }
    if (!squad) return Promise.resolve({ ok: false, reason: "no_squad" });
    const name = (id: string) => this.profiles.get(id)?.displayName ?? "";
    const members = [
      { id: squad.ownerId, name: name(squad.ownerId), joinedAt: iso(squad.createdAt), isOwner: true },
      ...this.#squadMembers(squad.id)
        .sort((a, b) => a.joinedAt - b.joinedAt || (a.userId < b.userId ? -1 : 1))
        .map((m) => ({ id: m.userId, name: name(m.userId), joinedAt: iso(m.joinedAt), isOwner: false })),
    ];
    return Promise.resolve({ ok: true, squadId: squad.id, ownerId: squad.ownerId, members });
  }

  squadRemove(actorId: string, memberId: string): Promise<RemoveResult> {
    const membership = this.members.find((m) => m.userId === memberId);
    if (!membership) return Promise.resolve({ ok: false, reason: "not_found" });
    const owner = this.squads.get(membership.squadId)!.ownerId;
    if (actorId !== owner && actorId !== memberId) return Promise.resolve({ ok: false, reason: "not_allowed" });
    this.members.splice(this.members.indexOf(membership), 1);
    return Promise.resolve({ ok: true });
  }

  // ---- Deletion ----

  deleteAiData(userId: string): Promise<void> {
    for (let i = this.requests.length - 1; i >= 0; i--) {
      if (this.requests[i].userId === userId) this.requests.splice(i, 1);
    }
    this.windows.delete(userId);
    return Promise.resolve();
  }

  deleteAccount(userId: string): Promise<void> {
    for (const squad of [...this.squads.values()].filter((s) => s.ownerId === userId)) {
      this.squads.delete(squad.id);
      for (let i = this.members.length - 1; i >= 0; i--) {
        if (this.members[i].squadId === squad.id) this.members.splice(i, 1);
      }
      for (const [code, inv] of this.invites) if (inv.squadId === squad.id) this.invites.delete(code);
    }
    for (let i = this.members.length - 1; i >= 0; i--) if (this.members[i].userId === userId) this.members.splice(i, 1);
    for (let i = this.entitlements.length - 1; i >= 0; i--) {
      if (this.entitlements[i].userId === userId) this.entitlements.splice(i, 1);
    }
    for (const key of [...this.counters.keys()]) if (key.startsWith(`${userId}|`)) this.counters.delete(key);
    this.windows.delete(userId);
    void this.deleteAiData(userId);
    this.profiles.delete(userId);
    this.deleted.add(userId);
    return Promise.resolve();
  }
}
