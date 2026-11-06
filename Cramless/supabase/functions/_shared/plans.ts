// Plans and quotas. Free: 3 AI scans a week (up to 10 pages each), 20 graded answers and 10 tutor messages a
// day, AI notes for 1 lecture a week; reviews are never metered (they're on the device). Paid plans (Pro, Squad,
// Exam Pass) are unlimited with fair use: a ceiling no student reaches in normal use, never shown as a limit.
// Under every plan's meters sits a cost cap: what a person's model calls may cost in a day (`dailyCostError`): 10¢ on the free plan, 40¢ on a paid
// plan, whose week (Monday to Sunday) may cost 70¢ (`weeklyCostError`), so that a cram night is possible and the average day is not more than before.
// Days and weeks are the person's local ones (their profile's time zone; weeks start on Monday).

import type { MeterKey, Period, Plan, QuotaMeter, QuotaStatus } from "./contract.ts";
import { ApiError } from "./errors.ts";

/** The metered things. `extras` covers check, confusions, cards-from-chat, syllabus and exam-mention, which the app never shows; `redeems` caps
 * Squad invite-code attempts, so codes can't be guessed; `drafts` counts what Cap drafts for the student (cards, questions,
 * notes, exams): 3 a day on the free plan; `research` counts web research, which is a Pro feature (the free allowance is
 * none); `rounds` counts the rounds of an assistant reply after its first, which is a `tutor` message: the relay refuses a
 * round when `rounds` would pass three for each `tutor` message that day, so a request made up by hand, with no first
 * round behind it, costs the same as an honest reply. */
export type Meter = MeterKey | "extras" | "redeems" | "drafts" | "research" | "rounds";

export interface MeterRule {
  period: Period;
  free: number;
  fairUse: number;
}

export const METERS: Record<Meter, MeterRule> = {
  scans: { period: "week", free: 3, fairUse: 150 },
  grades: { period: "day", free: 20, fairUse: 1500 },
  tutor: { period: "day", free: 10, fairUse: 300 },
  lectures: { period: "week", free: 1, fairUse: 40 },
  extras: { period: "day", free: 120, fairUse: 800 },
  redeems: { period: "day", free: 10, fairUse: 10 },
  drafts: { period: "day", free: 3, fairUse: 150 },
  research: { period: "day", free: 0, fairUse: 3 },
  rounds: { period: "day", free: 30, fairUse: 900 },
};

/** The meters the app shows, in this order. */
export const SHOWN_METERS: readonly MeterKey[] = ["scans", "grades", "tutor", "lectures"];

/** Pages in one AI scan. */
export const PAGES_PER_SCAN: Record<"free" | "paid", number> = { free: 10, paid: 40 };

/** Page transcriptions and the generate call that follows them count as one scan within this window. */
export const SCAN_WINDOW_MINUTES = 30;

export function isPaid(plan: Plan): boolean {
  return plan !== "free";
}

/** The enforced limit: the free quota, or the fair-use ceiling on a paid plan. */
export function enforcedLimit(meter: Meter, plan: Plan): number {
  return isPaid(plan) ? METERS[meter].fairUse : METERS[meter].free;
}

/** The limit the app shows: null (unlimited) on a paid plan. */
export function shownLimit(meter: Meter, plan: Plan): number | null {
  return isPaid(plan) ? null : METERS[meter].free;
}

/** The time zone, if the runtime knows it; UTC otherwise. */
export function safeTimeZone(zone: string | null | undefined): string {
  if (!zone) return "UTC";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
    return zone;
  } catch {
    return "UTC";
  }
}

function localParts(at: Date, timeZone: string): { y: number; m: number; d: number; h: number; min: number } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(at);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? "0");
  return { y: get("year"), m: get("month"), d: get("day"), h: get("hour"), min: get("minute") };
}

function ymd(y: number, m: number, d: number): string {
  return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/** The first day of the period containing `now`, in the person's calendar: "2026-10-22" for a day, the Monday
 * for a week. */
export function periodStart(period: Period, now: Date, timeZone: string): string {
  const { y, m, d } = localParts(now, safeTimeZone(timeZone));
  if (period === "day") return ymd(y, m, d);
  const utc = new Date(Date.UTC(y, m - 1, d));
  const back = (utc.getUTCDay() + 6) % 7; // days since Monday
  utc.setUTCDate(utc.getUTCDate() - back);
  return ymd(utc.getUTCFullYear(), utc.getUTCMonth() + 1, utc.getUTCDate());
}

/** The instant local midnight starts `day` ("yyyy-MM-dd") in the zone. */
export function localMidnight(day: string, timeZone: string): Date {
  const zone = safeTimeZone(timeZone);
  const [y, m, d] = day.split("-").map(Number);
  let guess = Date.UTC(y, m - 1, d, 0, 0);
  for (let i = 0; i < 3; i++) {
    const p = localParts(new Date(guess), zone);
    const asLocal = Date.UTC(p.y, p.m - 1, p.d, p.h, p.min);
    const target = Date.UTC(y, m - 1, d, 0, 0);
    const delta = asLocal - target;
    if (delta === 0) break;
    guess -= delta;
  }
  return new Date(guess);
}

/** When the period containing `now` ends. */
export function periodEnd(period: Period, now: Date, timeZone: string): Date {
  const start = periodStart(period, now, timeZone);
  const [y, m, d] = start.split("-").map(Number);
  const next = new Date(Date.UTC(y, m - 1, d + (period === "day" ? 1 : 7)));
  return localMidnight(ymd(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate()), timeZone);
}

/** The (meter, period start) pairs for a quota report. */
export function usageKeys(meters: readonly Meter[], now: Date, timeZone: string): { meter: Meter; period: string }[] {
  return meters.map((meter) => ({ meter, period: periodStart(METERS[meter].period, now, timeZone) }));
}

/** The app's quota report for a plan and its usage. */
export function quotaStatus(plan: Plan, usage: Partial<Record<Meter, number>>): QuotaStatus {
  return {
    plan,
    meters: SHOWN_METERS.map((key): QuotaMeter => ({
      key,
      used: usage[key] ?? 0,
      limit: shownLimit(key, plan),
      period: METERS[key].period,
    })),
  };
}

const FREE_MESSAGES: Record<Meter, string> = {
  scans:
    "That's this week's 3 AI scans on the free plan. Scanning on your iPhone still works, and it resets on Monday.",
  grades: "That's today's 20 graded answers on the free plan. Quick check still works, and it resets at midnight.",
  tutor: "That's today's 10 tutor messages on the free plan. It resets at midnight.",
  lectures:
    "That's this week's AI notes for 1 lecture on the free plan. Transcripts still work, and it resets on Monday.",
  extras: "That's today's AI requests on the free plan. It resets at midnight.",
  redeems: "That's too many invite codes for today. Check the code with your friend and try again tomorrow.",
  drafts: "That's today's 3 free drafts on the free plan. Capling Pro lifts the daily limit.",
  research: "Web research is part of Capling Pro.",
  rounds: "That's today's 10 tutor messages on the free plan. It resets at midnight.",
};

const FAIR_USE_NAMES: Record<Meter, string> = {
  scans: "AI scans",
  grades: "graded answers",
  tutor: "tutor messages",
  lectures: "lecture notes",
  extras: "AI requests",
  redeems: "invite codes",
  drafts: "drafts",
  research: "web research",
  rounds: "tutor messages",
};

/** The 429 for the day's cost cap (DEFAULT_DAILY_COST_CAP_NANO in cost.ts). No meter ran out, so it names none; `retryAfter` is the time
 * to the person's local midnight. The words are for every plan: the app shows them on a paid plan and in the chat's note. */
export function dailyCostError(plan: Plan, now: Date, timeZone: string): ApiError {
  const retryAfter = Math.max(1, Math.ceil((periodEnd("day", now, timeZone).getTime() - now.getTime()) / 1000));
  return new ApiError("quota_exceeded", "That's all the cloud AI for today. It starts again at midnight.", {
    quota: { plan, meters: [] },
    retryAfter,
  });
}

/** The 429 for a paid person's week cost cap: the same words, until Monday's local midnight. */
export function weeklyCostError(plan: Plan, now: Date, timeZone: string): ApiError {
  const retryAfter = Math.max(1, Math.ceil((periodEnd("week", now, timeZone).getTime() - now.getTime()) / 1000));
  return new ApiError("quota_exceeded", "That's all the cloud AI for this week. It starts again on Monday.", {
    quota: { plan, meters: [] },
    retryAfter,
  });
}

/** The 429 for a meter that ran out. On the free plan it matches the app's copy (fixtures/error-quota.json);
 * on a paid plan it's the fair-use ceiling and says when to retry. */
export function quotaError(meter: Meter, plan: Plan, used: number, now: Date, timeZone: string): ApiError {
  const rule = METERS[meter];
  const shown: QuotaStatus = {
    plan,
    meters:
      meter === "extras" || meter === "redeems" || meter === "drafts" || meter === "research" || meter === "rounds"
        ? []
        : [{ key: meter, used, limit: shownLimit(meter, plan), period: rule.period }],
  };
  if (!isPaid(plan) || meter === "redeems") {
    return new ApiError("quota_exceeded", FREE_MESSAGES[meter], { quota: shown });
  }
  const retryAfter = Math.max(1, Math.ceil((periodEnd(rule.period, now, timeZone).getTime() - now.getTime()) / 1000));
  const when = rule.period === "day" ? "today" : "this week";
  return new ApiError(
    "quota_exceeded",
    `That's the fair-use limit for ${FAIR_USE_NAMES[meter]} ${when}. It resets ${
      rule.period === "day" ? "at midnight" : "on Monday"
    }.`,
    { quota: shown, retryAfter },
  );
}
