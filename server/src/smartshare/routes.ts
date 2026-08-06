/**
 * Smart Share Links — HTTP surface.
 *
 * Four routes, all under /v1/smart-share/:
 *   GET  /platforms  — platform config for the UI (no auth, cacheable)
 *   POST /campaigns  — validate a draft and return its share link (no model call)
 *   POST /resolve    — decode a link into a campaign for display (no model call)
 *   POST /generate   — write one post for a campaign + platform (model call)
 *
 * ## Abuse surface
 *
 * /generate is necessarily unauthenticated: the whole point is that strangers
 * open a link. That makes it the only route in this Worker that can spend
 * Anthropic budget without a device id or license key, so it carries three
 * independent brakes:
 *
 *   1. Per-IP burst limit (SHARE_LIMITER, Cloudflare Rate Limiting API).
 *   2. A global daily ceiling in KV, with its own counter so Smart Share can
 *      never eat the paste product's trial or licensed capacity.
 *   3. A hard cap on request body size, campaign payload size, and prompt inputs.
 *
 * If the daily ceiling is hit the route fails closed with a plain message. That
 * is the correct failure mode for a cost cap.
 */

import { NoopSmartShareAnalytics, type SmartShareAnalytics } from "./analytics.ts";
import { extractTokenFromLink } from "./codec.ts";
import { GenerationError, generateShareCopy } from "./generate.ts";
import { buildDestinationUrl, platformDirectory } from "./platforms.ts";
import { EncodedLinkCampaignProvider, type SmartShareCampaignProvider } from "./provider.ts";
import {
  SmartShareError,
  assertUsableCampaign,
  isSmartSharePlatform,
  parseCampaignDraft,
} from "./schema.ts";

interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

/** Only the bindings Smart Share needs. The Worker's Env extends this. */
export interface SmartShareEnv {
  ANTHROPIC_API_KEY: string;
  SUPERPASTE_KV: KVNamespace;
  /** Per-IP burst limiter for Smart Share (see wrangler.toml). */
  SHARE_LIMITER?: RateLimiter;
  /** Daily ceiling on Smart Share generations. Its own counter, on purpose. */
  GLOBAL_SHARE_DAILY_LIMIT?: string;
  /** Origin share links are built against. Defaults to the public site. */
  SMART_SHARE_BASE_URL?: string;
}

const ROUTE_PREFIX = "/v1/smart-share/";

const DEFAULT_BASE_URL = "https://superpaste.ai";
const DEFAULT_GLOBAL_SHARE_DAILY_LIMIT = 500;

/** Bounds the JSON we will even read. A campaign link is a few KB at most. */
const MAX_REQUEST_BYTES = 32 * 1024;

/** Regeneration context limits — these bound prompt size, so they are enforced. */
const MAX_PREVIOUS_DRAFTS = 3;
const MAX_PREVIOUS_DRAFT_CHARS = 400;

/**
 * Origins allowed to call these routes from a browser.
 *
 * An allowlist rather than `*`: these endpoints spend money, so any page that
 * can invoke them should be one we ship. localhost entries are for `wrangler
 * dev` against a locally served copy of website/.
 */
const ALLOWED_ORIGINS = new Set([
  "https://superpaste.ai",
  "https://www.superpaste.ai",
  "http://localhost:8788",
  "http://localhost:3000",
  "http://127.0.0.1:8788",
]);

function corsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = { Vary: "Origin" };
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
    headers["Access-Control-Allow-Headers"] = "Content-Type";
    headers["Access-Control-Max-Age"] = "86400";
  }
  return headers;
}

function json(body: unknown, status: number, origin: string | null, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders(origin), ...extra },
  });
}

function todayUTC(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Read a JSON body with a hard size ceiling.
 *
 * Content-Length is checked first as a cheap rejection, then the decoded text is
 * measured because the header is client-supplied and may be absent or lying.
 */
async function readJsonBody(request: Request): Promise<unknown> {
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_REQUEST_BYTES) {
    throw new SmartShareError("payload_too_large", "Request body is too large.");
  }
  const text = await request.text();
  if (text.length > MAX_REQUEST_BYTES) {
    throw new SmartShareError("payload_too_large", "Request body is too large.");
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new SmartShareError("invalid_campaign", "Request body must be JSON.");
  }
}

async function enforceGlobalShareLimit(env: SmartShareEnv): Promise<void> {
  const limit = parseInt(env.GLOBAL_SHARE_DAILY_LIMIT ?? "", 10) || DEFAULT_GLOBAL_SHARE_DAILY_LIMIT;
  const key = `global:smartshare:usage:${todayUTC()}`;
  const current = parseInt((await env.SUPERPASTE_KV.get(key)) ?? "0", 10);
  if (current >= limit) {
    throw new GenerationError(
      "Smart Share is at capacity for today. Try again after midnight UTC.",
      429,
    );
  }
}

/** Same non-atomic counter pattern the paste path uses; close enough at this scale. */
async function bumpShareCounter(env: SmartShareEnv): Promise<void> {
  const key = `global:smartshare:usage:${todayUTC()}`;
  const current = parseInt((await env.SUPERPASTE_KV.get(key)) ?? "0", 10);
  await env.SUPERPASTE_KV.put(key, String(current + 1), { expirationTtl: 48 * 3600 });
}

/** Short, non-reversible reference for the analytics seam. Never the campaign id. */
async function campaignRef(id: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(id));
  return [...new Uint8Array(digest)]
    .slice(0, 6)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function readPreviousDrafts(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((entry): entry is string => typeof entry === "string")
    .slice(-MAX_PREVIOUS_DRAFTS)
    .map((entry) => entry.slice(0, MAX_PREVIOUS_DRAFT_CHARS));
}

/**
 * Seeds come from the client so a Regenerate press is guaranteed to differ from
 * the draft on screen. A hostile seed only changes which angle that caller gets,
 * so it needs range-clamping, not trust.
 */
function readSeed(raw: unknown): number {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Math.abs(Math.trunc(raw)) % 1_000_000;
  }
  return Math.floor(Math.random() * 1_000_000);
}

export interface SmartShareDeps {
  provider?: SmartShareCampaignProvider;
  analytics?: SmartShareAnalytics;
}

/** True when this request belongs to Smart Share. */
export function isSmartShareRoute(pathname: string): boolean {
  return pathname.startsWith(ROUTE_PREFIX);
}

/**
 * Handle a Smart Share request. Returns null when the path is not a Smart Share
 * route, so the caller can fall through to its own routing.
 */
export async function handleSmartShareRequest(
  request: Request,
  env: SmartShareEnv,
  ctx: ExecutionContext,
  deps: SmartShareDeps = {},
): Promise<Response | null> {
  const url = new URL(request.url);
  if (!isSmartShareRoute(url.pathname)) return null;

  const origin = request.headers.get("Origin");
  const route = url.pathname.slice(ROUTE_PREFIX.length);
  const provider = deps.provider ?? new EncodedLinkCampaignProvider();
  const analytics = deps.analytics ?? new NoopSmartShareAnalytics();

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  // --- GET /v1/smart-share/platforms ---
  if (route === "platforms") {
    if (request.method !== "GET") {
      return json({ error: "method_not_allowed" }, 405, origin);
    }
    return json({ platforms: platformDirectory() }, 200, origin, {
      "Cache-Control": "public, max-age=3600",
    });
  }

  // --- POST /v1/smart-share/campaigns ---
  if (route === "campaigns") {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405, origin);
    }
    try {
      const body = await readJsonBody(request);
      const parsed = parseCampaignDraft(body);
      if (!parsed.ok) {
        return json({ error: "invalid_campaign", details: parsed.errors }, 400, origin);
      }
      const campaign = await provider.createCampaign(parsed.value);
      const baseUrl = env.SMART_SHARE_BASE_URL ?? DEFAULT_BASE_URL;
      return json(
        { id: campaign.id, url: provider.shareLinkFor(campaign, baseUrl), campaign },
        200,
        origin,
      );
    } catch (err) {
      if (err instanceof SmartShareError) {
        return json({ error: err.code, message: err.message, details: err.details }, 400, origin);
      }
      console.error("Smart Share campaign creation failed:", err);
      return json({ error: "internal_error", message: "Couldn't create the campaign." }, 500, origin);
    }
  }

  // --- POST /v1/smart-share/resolve ---
  // Decodes a link so the share page can show the campaign before generating.
  // Pure CPU work with no model call, so it carries no rate limiter of its own —
  // putting it behind SHARE_LIMITER would spend the generation budget just to
  // render a page.
  if (route === "resolve") {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405, origin);
    }
    try {
      const body = await readJsonBody(request);
      const raw =
        typeof body === "object" && body !== null
          ? (body as Record<string, unknown>).campaign
          : undefined;
      const token = typeof raw === "string" ? extractTokenFromLink(raw) : null;
      if (!token) {
        return json({ error: "invalid_link", message: "This Smart Share link isn't valid." }, 400, origin);
      }

      const campaign = await provider.getCampaign(token);
      analytics.record({ type: "link_opened", campaignRef: await campaignRef(campaign.id) });

      const supported = platformDirectory().filter((entry) =>
        campaign.supportedPlatforms.includes(entry.id),
      );
      return json(
        {
          campaign: {
            // Deliberately does not echo `id`: the page already holds the token
            // and re-serving it only widens where the payload can be logged.
            name: campaign.name,
            intent: campaign.intent,
            requiredUrl: campaign.requiredUrl,
            requiredFacts: campaign.requiredFacts,
            hashtags: campaign.hashtags,
            tone: campaign.tone,
            prohibitedClaims: campaign.prohibitedClaims,
            supportedPlatforms: campaign.supportedPlatforms,
            expiresAt: campaign.expiresAt,
            createdAt: campaign.createdAt,
          },
          platforms: supported,
        },
        200,
        origin,
      );
    } catch (err) {
      if (err instanceof SmartShareError) {
        const status = err.code === "campaign_expired" ? 410 : 400;
        return json({ error: err.code, message: err.message, details: err.details }, status, origin);
      }
      console.error("Smart Share resolve failed:", err);
      return json({ error: "internal_error", message: "Couldn't read the link." }, 500, origin);
    }
  }

  // --- POST /v1/smart-share/generate ---
  if (route === "generate") {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405, origin);
    }

    const clientIP = request.headers.get("CF-Connecting-IP") ?? "unknown";
    if (env.SHARE_LIMITER) {
      const { success } = await env.SHARE_LIMITER.limit({ key: clientIP });
      if (!success) {
        return json(
          { error: "too_many_requests", message: "Too many requests. Slow down." },
          429,
          origin,
        );
      }
    }

    try {
      const body = await readJsonBody(request);
      if (typeof body !== "object" || body === null) {
        return json({ error: "invalid_campaign", message: "Body must be a JSON object." }, 400, origin);
      }
      const input = body as Record<string, unknown>;

      const platform = input.platform;
      if (!isSmartSharePlatform(platform)) {
        return json({ error: "unsupported_platform", message: "Unknown platform." }, 400, origin);
      }

      // Accept a bare token or a full share URL, so a user who pasted the whole
      // link into the "load a campaign" box still works.
      const rawCampaign = typeof input.campaign === "string" ? input.campaign : "";
      const token = extractTokenFromLink(rawCampaign);
      if (!token) {
        return json({ error: "invalid_link", message: "This Smart Share link isn't valid." }, 400, origin);
      }

      const campaign = await provider.getCampaign(token);
      assertUsableCampaign(campaign, platform);

      await enforceGlobalShareLimit(env);

      const ref = await campaignRef(campaign.id);
      const previousDrafts = readPreviousDrafts(input.previousDrafts);
      const seed = readSeed(input.seed);

      const result = await generateShareCopy({
        campaign,
        platform,
        seed,
        previousDrafts,
        apiKey: env.ANTHROPIC_API_KEY,
      });

      // Count every generation that reached the model, matching how the paste
      // path counts: only-on-success would let upstream errors run uncapped.
      ctx.waitUntil(bumpShareCounter(env));
      analytics.record({
        type: "copy_generated",
        campaignRef: ref,
        platform,
        regeneration: previousDrafts.length > 0,
      });

      return json(
        {
          text: result.text,
          subject: result.subject,
          warnings: result.warnings,
          platform: result.platform,
          angle: result.angle,
          seed: result.seed,
          destinationUrl: buildDestinationUrl(
            platform,
            result.text,
            campaign.requiredUrl,
            result.subject,
          ),
        },
        200,
        origin,
      );
    } catch (err) {
      if (err instanceof SmartShareError) {
        const status = err.code === "campaign_expired" ? 410 : 400;
        return json({ error: err.code, message: err.message, details: err.details }, status, origin);
      }
      if (err instanceof GenerationError) {
        return json({ error: "generation_failed", message: err.message }, err.status, origin);
      }
      console.error("Smart Share generation failed:", err);
      return json({ error: "internal_error", message: "Couldn't write the post." }, 500, origin);
    }
  }

  return json({ error: "not_found" }, 404, origin);
}
