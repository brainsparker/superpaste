/**
 * Smart Share Links — HTTP surface.
 *
 * Three routes, all under /v1/smart-share/:
 *   GET  /platforms  — platform config for the UI (no auth, cacheable)
 *   POST /campaigns  — validate a draft and return its share link (no model call)
 *   POST /resolve    — decode a link into a campaign for display (no model call)
 *
 * ## No generation here, on purpose
 *
 * None of these routes calls a model, so none of them can spend Anthropic
 * budget. Generation happens only through POST /v1/messages in the app, behind
 * the existing device-id + trial/license gate.
 *
 * An earlier version exposed an anonymous /generate here so a stranger could
 * generate from a browser. That was an open inference faucet: campaign creation
 * is unauthenticated and `intent` is free text, so anyone could create a
 * campaign and generate against it without ever holding a licence. Rate limits
 * only slow that down. Moving generation into the app closes it outright, and
 * every generation now costs its user quota like any other paste.
 *
 * These three stay unauthenticated because they are pure CPU: validating a
 * draft, encoding a link, decoding one for display. Body size is still capped.
 */

import { NoopSmartShareAnalytics, type SmartShareAnalytics } from "./analytics.ts";
import { extractTokenFromLink } from "./codec.ts";
import { platformDirectory } from "./platforms.ts";
import { EncodedLinkCampaignProvider, type SmartShareCampaignProvider } from "./provider.ts";
import { SmartShareError, parseCampaignDraft } from "./schema.ts";

/**
 * Only the bindings Smart Share needs. The Worker's Env extends this.
 *
 * No API key and no rate limiter: these routes never reach a model.
 */
export interface SmartShareEnv {
  /** Origin share links are built against. Defaults to the public site. */
  SMART_SHARE_BASE_URL?: string;
}

const ROUTE_PREFIX = "/v1/smart-share/";

const DEFAULT_BASE_URL = "https://superpaste.ai";
/** Bounds the JSON we will even read. A campaign link is a few KB at most. */
const MAX_REQUEST_BYTES = 32 * 1024;

/**
 * Origins allowed to call these routes from a browser. An allowlist rather than
 * `*` so only pages we ship can drive them. localhost entries are for
 * `wrangler dev` against a locally served copy of website/.
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

/** Short, non-reversible reference for the analytics seam. Never the campaign id. */
async function campaignRef(id: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(id));
  return [...new Uint8Array(digest)]
    .slice(0, 6)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
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

  return json({ error: "not_found" }, 404, origin);
}
