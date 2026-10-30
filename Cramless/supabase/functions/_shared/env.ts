// Function secrets and switches (supabase/functions/.env.example lists them). Never logged or echoed.

import { RESEARCH_DOMAINS } from "./assistant.ts";
import { DEFAULT_DAILY_COST_CAP_NANO, parseUsd, TERRA } from "./cost.ts";

export const DEFAULT_BUNDLE_ID = "com.loopware.Capling";
export const DEFAULT_INVITE_BASE_URL = "https://capling.app/squad/";

export interface Env {
  supabaseUrl: string;
  serviceRoleKey: string;
  anthropicApiKey: string;
  /** Tests and local mocks only. Empty: the SDK's default (https://api.anthropic.com). */
  anthropicBaseUrl: string;
  /** With it, Ask Cap's tutor answers from OpenAI; every other route stays on Claude. */
  openaiApiKey: string;
  /** Tests and local mocks only. Empty: https://api.openai.com/v1. */
  openaiBaseUrl: string;
  /** The OpenAI model that answers the tutor, and how much it thinks first. */
  tutorModel: string;
  tutorEffort: "low" | "medium" | "high";
  /** The sites web research may read (RESEARCH_DOMAINS replaces the built-in list). */
  researchDomains: string[];
  /** The most one person's model calls may cost in a day, in nano-dollars (DAILY_COST_CAP_USD, default 10¢); 0 turns it off. */
  dailyCostCapNano: bigint;
  /** CRAMLESS_MOCK=1: the AI routes serve the fixtures. */
  mock: boolean;
  bundleId: string;
  /** The app's numeric Apple ID; null when unset (Production notifications then fail verification). */
  appAppleId: number | null;
  /** CRAMLESS_ALLOW_XCODE_JWS=1, honoured only on a local stack. */
  allowXcodeJws: boolean;
  inviteBaseUrl: string;
  localProject: boolean;
  /** Configuration problems found at start-up, logged at every cold start. */
  faults: string[];
}

/** The hosts that count as a local stack. */
export function isLocalUrl(url: string): boolean {
  let host: string;
  try {
    host = new URL(url).hostname.toLowerCase();
  } catch {
    return false;
  }
  if (["127.0.0.1", "localhost", "kong", "host.docker.internal"].includes(host)) return true;
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return false;
  const [a, b] = [Number(m[1]), Number(m[2])];
  return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

/** The service key the platform injects: SUPABASE_SECRET_KEYS (new), else SUPABASE_SERVICE_ROLE_KEY. */
function serviceKey(get: (name: string) => string): string {
  const keys = get("SUPABASE_SECRET_KEYS");
  if (keys) {
    try {
      const parsed = JSON.parse(keys) as Record<string, string>;
      const first = parsed.default ?? Object.values(parsed)[0];
      if (first) return first;
    } catch {
      // fall through to the single key
    }
  }
  return get("SUPABASE_SECRET_KEY") || get("SUPABASE_SERVICE_ROLE_KEY");
}

export function envFrom(get: (name: string) => string): Env {
  const faults: string[] = [];
  const supabaseUrl = get("SUPABASE_URL");
  const localProject = isLocalUrl(supabaseUrl);
  const mock = get("CRAMLESS_MOCK") === "1";
  const anthropicApiKey = get("ANTHROPIC_API_KEY");
  if (!mock && !anthropicApiKey) faults.push("anthropic_key_missing");
  const asked = get("OPENAI_TUTOR_EFFORT");
  const tutorEffort = asked === "medium" || asked === "high" ? asked : "low";
  if (asked && asked !== tutorEffort) faults.push("openai_tutor_effort_invalid");
  const listed = get("RESEARCH_DOMAINS").split(/[\s,]+/).map((d) => d.trim().toLowerCase()).filter((d) =>
    /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(d)
  );
  if (get("RESEARCH_DOMAINS").trim() && listed.length === 0) faults.push("research_domains_invalid");
  const capAsked = get("DAILY_COST_CAP_USD").trim();
  const cap = capAsked ? parseUsd(capAsked) : null;
  if (capAsked && cap === null) faults.push("daily_cost_cap_invalid");
  if (mock && !localProject) faults.push("mock_mode_on_hosted_project");
  const xcodeAsked = get("CRAMLESS_ALLOW_XCODE_JWS") === "1";
  if (xcodeAsked && !localProject) faults.push("xcode_jws_ignored");
  const appId = Number(get("APPLE_APP_ID"));
  const appAppleId = Number.isInteger(appId) && appId > 0 ? appId : null;
  if (appAppleId === null && !localProject) faults.push("apple_app_id_missing");
  return {
    supabaseUrl,
    serviceRoleKey: serviceKey(get),
    anthropicApiKey,
    anthropicBaseUrl: get("ANTHROPIC_BASE_URL").replace(/\/+$/, ""),
    openaiApiKey: get("OPENAI_API_KEY"),
    openaiBaseUrl: get("OPENAI_BASE_URL").replace(/\/+$/, ""),
    tutorModel: get("OPENAI_TUTOR_MODEL") || TERRA,
    tutorEffort,
    researchDomains: listed.length > 0 ? [...new Set(listed)].slice(0, 100) : [...RESEARCH_DOMAINS],
    dailyCostCapNano: cap ?? DEFAULT_DAILY_COST_CAP_NANO,
    mock,
    bundleId: get("APPLE_BUNDLE_ID") || DEFAULT_BUNDLE_ID,
    appAppleId,
    allowXcodeJws: xcodeAsked && localProject,
    inviteBaseUrl: get("CRAMLESS_INVITE_BASE_URL") || DEFAULT_INVITE_BASE_URL,
    localProject,
    faults,
  };
}

export function envFromDeno(): Env {
  return envFrom((name) => Deno.env.get(name) ?? "");
}
