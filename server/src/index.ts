/**
 * SuperPaste API Proxy
 *
 * Owns the Anthropic request end-to-end: the client sends only the captured
 * context (image + window metadata + response settings) and this Worker builds
 * the model call. Clients can no longer choose the model, max_tokens, or
 * system prompt — that closed an open-proxy hole and lets prompt improvements
 * ship without a new app release.
 *
 * Also handles trial enforcement, rate limiting, and license key validation.
 *
 * Deploy: `cd server && npx wrangler deploy`
 * Secrets: ANTHROPIC_API_KEY, POLAR_ACCESS_TOKEN, POLAR_ORGANIZATION_ID
 * KV: SUPERPASTE_KV (create with `wrangler kv namespace create SUPERPASTE_KV`)
 */

import { buildSystemPrompt, validatePasteRequest, textBlocksOnly, MAX_TEXT_FIELD_CHARS, type PasteRequest } from "./paste.ts";
import { readJsonBody, RequestError } from "./request.ts";
import { trialPrincipal } from "./quota.ts";
export { QuotaLedger } from "./quota.ts";

import { extractTokenFromLink } from "./smartshare/codec.ts";
import { detectPlatform, resolveTargetPlatform } from "./smartshare/detect.ts";
import { buildSmartSharePrompt, finalizeShareCopy } from "./smartshare/prompt.ts";
import { EncodedLinkCampaignProvider } from "./smartshare/provider.ts";
import { handleSmartShareRequest, type SmartShareEnv } from "./smartshare/routes.ts";
import { SmartShareError, type SmartShareCampaign, type SmartSharePlatform } from "./smartshare/schema.ts";

interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env extends SmartShareEnv {
  ANTHROPIC_API_KEY: string;
  POLAR_ACCESS_TOKEN: string;
  POLAR_ORGANIZATION_ID: string;
  SUPERPASTE_KV: KVNamespace;
  QUOTA_LEDGER: DurableObjectNamespace;
  /** Stable secret for pseudonymous network trial identities; rotation resets trials. */
  TRIAL_IDENTITY_SECRET?: string;
  /** Per-IP burst limiters (Cloudflare Rate Limiting API, configured in wrangler.toml). */
  IP_LIMITER: RateLimiter;
  VALIDATE_LIMITER: RateLimiter;
  /** Daily request ceilings, split so trial abuse can never lock out paying customers. */
  GLOBAL_TRIAL_DAILY_LIMIT?: string;
  GLOBAL_LICENSED_DAILY_LIMIT?: string;
  /** Optional owner/developer bypass key. Set via `wrangler secret put OWNER_LICENSE_KEY`.
   *  When the presented license key equals this value, validation succeeds without
   *  calling Polar — used by the creator to exercise the app without a paid license.
   *  Kept out of source on purpose so the value never ships in the OSS repo. */
  OWNER_LICENSE_KEY?: string;
}

const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const REQUEST_BUDGET_MS = 35_000;

const MODEL = "claude-sonnet-5-5";
const MAX_TOKENS = 2048;
/** A social post is short; a tighter ceiling bounds Magic Copy's cost. */
const SHARE_MAX_TOKENS = 1024;

const DEFAULT_GLOBAL_TRIAL_DAILY_LIMIT = 300;
const DEFAULT_GLOBAL_LICENSED_DAILY_LIMIT = 2000;

const LICENSE_CACHE_TTL_SECONDS = 3600; // positive result: 1 hour
const LICENSE_NEGATIVE_TTL_SECONDS = 300; // negative result: 5 min, so fresh buyers aren't locked out

/**
 * Magic Copy: the user has a Smart Share campaign link on the clipboard and
 * pressed the hotkey in a composer. No screenshot is involved — the campaign
 * supplies the content and the frontmost app supplies the destination — so this
 * is a separate request shape rather than a variant of PasteRequest.
 *
 * It rides the same `/v1/messages` route on purpose: trial enforcement, license
 * validation, per-IP limits, daily caps, and usage counters then apply
 * unchanged, and Magic Copy costs the user quota exactly like a normal paste.
 * That is also what keeps campaign generation from being an open, anonymous
 * endpoint anyone could mine for free inference.
 */
interface ShareRequest {
  share_link: string;
  bundle_id?: string;
  app_name?: string;
  window_title?: string;
}

const MAX_SHARE_LINK_CHARS = 8192;

// --- Helper: JSON response ---
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// --- Helper: SHA-256 hex, so raw license keys never become KV key names ---
async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// --- Request validation ---

/** Validate a Magic Copy request. Field caps mirror the paste request's. */
function validateShareRequest(b: Record<string, unknown>): { ok: true; req: ShareRequest } | { ok: false; error: string } {
  if (typeof b.share_link !== "string") {
    return { ok: false, error: "share_link must be a string" };
  }
  if (b.share_link.length === 0 || b.share_link.length > MAX_SHARE_LINK_CHARS) {
    return { ok: false, error: "share_link is empty or too long" };
  }
  for (const field of ["bundle_id", "app_name", "window_title"]) {
    if (b[field] !== undefined && typeof b[field] !== "string") {
      return { ok: false, error: `${field} must be a string` };
    }
  }
  return {
    ok: true,
    req: {
      share_link: b.share_link,
      bundle_id: (b.bundle_id as string | undefined)?.slice(0, MAX_TEXT_FIELD_CHARS),
      app_name: (b.app_name as string | undefined)?.slice(0, MAX_TEXT_FIELD_CHARS),
      window_title: (b.window_title as string | undefined)?.slice(0, MAX_TEXT_FIELD_CHARS),
    },
  };
}

// --- License key validation (Polar.sh) ---
async function validateLicense(key: string, env: Env, deadline: number): Promise<boolean> {
  // Owner/developer bypass — value lives in a Cloudflare secret, never in source.
  if (env.OWNER_LICENSE_KEY && key === env.OWNER_LICENSE_KEY) {
    return true;
  }

  const keyHash = await sha256(key);
  const cacheKey = `license_valid:${keyHash}`;

  const cached = await env.SUPERPASTE_KV.get(cacheKey);
  if (cached !== null) {
    return cached === "1";
  }

  // Only a positive cached validation grants outage grace, bounded by its TTL.
  let isValid: boolean;
  try {
    if (Date.now() >= deadline) throw new Error("Request deadline exceeded");
    const response = await fetch("https://api.polar.sh/v1/license-keys/validate", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${env.POLAR_ACCESS_TOKEN}`,
      },
      body: JSON.stringify({
        key,
        organization_id: env.POLAR_ORGANIZATION_ID,
      }),
      signal: AbortSignal.timeout(Math.max(1, Math.min(8_000, deadline - Date.now()))),
    });
    if (response.status === 401 || response.status === 403 || response.status === 429 || response.status >= 500) {
      console.error(`Polar auth failed (${response.status}) — check POLAR_ACCESS_TOKEN / POLAR_ORGANIZATION_ID`);
      throw new Error("License validation unavailable");
    }
    isValid = response.ok;
  } catch {
    throw { status: 503, error: "license_service_unavailable", message: "Couldn't verify this license. Try again shortly." };
  }

  await env.SUPERPASTE_KV.put(cacheKey, isValid ? "1" : "0", {
    expirationTtl: isValid ? LICENSE_CACHE_TTL_SECONDS : LICENSE_NEGATIVE_TTL_SECONDS,
  });

  return isValid;
}

async function handleRequest(request: Request, env: Env, deadline: number): Promise<Response> {
    const url = new URL(request.url);
    const clientIP = request.headers.get("CF-Connecting-IP") ?? "unknown";

    // --- Routes: /v1/smart-share/* ---
    // These non-generating routes have bounded request readers.
    // Return null for anything that is not a Smart Share path,
    // so the paste routes below are unaffected.
    const smartShareResponse = await handleSmartShareRequest(request, env);
    if (smartShareResponse) return smartShareResponse;

    // --- Route: POST /v1/validate-license ---
    if (request.method === "POST" && url.pathname === "/v1/validate-license") {
      const { success } = await env.VALIDATE_LIMITER.limit({ key: clientIP });
      if (!success) {
        return json({ error: "too_many_requests", message: "Too many requests. Slow down." }, 429);
      }

      try {
        const body = await readJsonBody(request, 4096, deadline);
        if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "bad_request" }, 400);
        const key = (body as Record<string, unknown>).key;
        if (typeof key !== "string" || key.trim().length === 0 || key.length > 512) return json({ valid: false, error: "invalid_key" }, 400);
        return json({ valid: await validateLicense(key.trim(), env, deadline) });
      } catch (err) {
        if (err instanceof RequestError) return json({ error: "bad_request", message: err.message }, err.status);
        const e = err as { status?: number; error?: string; message?: string };
        return json({ error: e.error ?? "internal_error", message: e.message ?? "Couldn't validate license." }, e.status ?? 503);
      }
    }

    // --- Route: POST /v1/messages ---
    if (request.method !== "POST" || url.pathname !== "/v1/messages") {
      return new Response("Not Found", { status: 404 });
    }

    const licenseKey = request.headers.get("X-License-Key");

    // Per-IP burst limit — X-Device-ID is client-controlled, so per-device
    // limits alone can be bypassed by rotating IDs. This can't.
    const { success } = await env.IP_LIMITER.limit({ key: clientIP });
    if (!success) {
      return json({ error: "too_many_requests", message: "Too many requests. Slow down." }, 429);
    }

    // Parse and validate the paste request before spending any quota.
    let rawBody: unknown;
    try {
      rawBody = await readJsonBody(request, 16*1024*1024, deadline);
    } catch (err) {
      return json({ error: "bad_request", message: err instanceof Error ? err.message : "Body must be JSON." }, err instanceof RequestError ? err.status : 400);
    }
    // Magic Copy and normal paste share this route so they share the trial,
    // license, and quota machinery below. They differ only in what they send
    // (a campaign link vs a screenshot) and how the model call is built.
    const isShareRequest =
      typeof rawBody === "object" &&
      rawBody !== null &&
      typeof (rawBody as Record<string, unknown>).share_link === "string";

    let pasteReq: PasteRequest | null = null;
    let shareReq: ShareRequest | null = null;
    let shareCampaign: SmartShareCampaign | null = null;
    let sharePlatform: SmartSharePlatform | null = null;

    if (isShareRequest) {
      const validatedShare = validateShareRequest(rawBody as Record<string, unknown>);
      if (!validatedShare.ok) {
        return json({ error: "bad_request", message: validatedShare.error }, 400);
      }
      shareReq = validatedShare.req;

      // Resolve the campaign BEFORE the quota gate: a dead link should cost the
      // user nothing, and decoding is pure CPU.
      const token = extractTokenFromLink(shareReq.share_link);
      if (!token) {
        return json(
          { error: "campaign_invalid", message: "That doesn't look like a Smart Share link." },
          422,
        );
      }
      try {
        shareCampaign = await new EncodedLinkCampaignProvider().getCampaign(token);
      } catch (err) {
        if (err instanceof SmartShareError) {
          const code = err.code === "campaign_expired" ? "campaign_expired" : "campaign_invalid";
          return json({ error: code, message: err.message }, 422);
        }
        throw err;
      }

      const detected = detectPlatform({
        bundleId: shareReq.bundle_id,
        appName: shareReq.app_name,
        windowTitle: shareReq.window_title,
      });
      sharePlatform = resolveTargetPlatform(shareCampaign, detected.platform).platform;
    } else {
      const validated = validatePasteRequest(rawBody);
      if (!validated.ok) {
        return json({ error: "bad_request", message: validated.error }, 400);
      }
      pasteReq = validated.req;
    }

    // Gate: license key or trial. Global caps sit BEHIND auth and are split by
    // tier so unauthenticated floods (or trial abuse) can't starve paying users.
    try {
      if (!env.QUOTA_LEDGER) return json({ error: "service_unavailable", message: "The service is temporarily unavailable." }, 503);
      let principal: string;
      let tier: "trial" | "licensed";
      if (licenseKey) {
        if (licenseKey.length > 512 || !await validateLicense(licenseKey, env, deadline)) return json({ error: "license_invalid", message: "License key is not valid." }, 403);
        tier = "licensed";
        principal = await sha256(licenseKey);
      } else {
        if (clientIP === "unknown" || !env.TRIAL_IDENTITY_SECRET || env.TRIAL_IDENTITY_SECRET.length < 32) return json({ error: "trial_unavailable", message: "Trial identity is unavailable. Try again later." }, 503);
        tier = "trial";
        principal = await trialPrincipal(clientIP, env.TRIAL_IDENTITY_SECRET);
      }
      const configured = Number(tier === "trial" ? env.GLOBAL_TRIAL_DAILY_LIMIT : env.GLOBAL_LICENSED_DAILY_LIMIT);
      const globalLimit = Number.isSafeInteger(configured) && configured > 0 ? configured : (tier === "trial" ? DEFAULT_GLOBAL_TRIAL_DAILY_LIMIT : DEFAULT_GLOBAL_LICENSED_DAILY_LIMIT);
      if (deadline - Date.now() < 1000) return json({ error: "timeout" }, 504);
      const ledger = env.QUOTA_LEDGER.get(env.QUOTA_LEDGER.idFromName(`${tier}-v1`));
      const reservation = await ledger.fetch("https://quota.internal/reserve", {
        method: "POST", body: JSON.stringify({ principal, tier, globalLimit }), signal: AbortSignal.timeout(Math.max(1, deadline-Date.now())),
      });
      if (!reservation.ok) return new Response(await reservation.text(), { status: reservation.status, headers: { "Content-Type": "application/json" } });
    } catch (err: unknown) {
      const e = err as { status?: number; error?: string; message?: string };
      return json({ error: e.error ?? "service_unavailable", message: e.message ?? "Couldn't reserve request capacity." }, e.status ?? 503);
    }

    // A storage/validation dependency may have outlived the response deadline.
    if (Date.now() >= deadline) return json({ error: "timeout" }, 504);
    // Build the Anthropic request server-side.
    const anthropicBody = shareCampaign && sharePlatform
      ? buildShareAnthropicBody(shareCampaign, sharePlatform)
      : buildPasteAnthropicBody(pasteReq!);

    let anthropicResponse: Response;
    try {
      anthropicResponse = await fetch(ANTHROPIC_MESSAGES_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": env.ANTHROPIC_API_KEY,
          "anthropic-version": ANTHROPIC_VERSION,
          "anthropic-beta": "server-side-fallback-2026-07-01",
        },
        body: JSON.stringify(anthropicBody),
        signal: AbortSignal.timeout(Math.max(1, deadline-Date.now())),
      });
    } catch (err) {
      console.error("Anthropic request failed:", err);
      return json({ error: "upstream_error", message: "The AI service didn't respond. Try again." }, 502);
    }

    // Reservations are durable before dispatch and remain charged on transport failure.
    let rawResponseBody: string;
    try { rawResponseBody = await anthropicResponse.text(); }
    catch { return json({ error: "upstream_error", message: "The AI service didn't respond. Try again." }, 502); }

    if (shareCampaign && sharePlatform) {
      // The paste path forwards Anthropic's error body as-is. Magic Copy must
      // not: a campaign comes from a third party, and an upstream error can echo
      // request content, so forwarding it would hand campaign text to the
      // sharer. Report a clean failure instead.
      if (!anthropicResponse.ok) {
        console.error(`Magic Copy upstream status ${anthropicResponse.status}`);
        return json(
          { error: "upstream_error", message: "Couldn't write the post. Try again." },
          502,
        );
      }

      // Magic Copy pastes without a review screen, so campaign guardrails are
      // enforced here rather than reported. The response is rebuilt in
      // Anthropic's shape so the client parses it exactly as a normal paste.
      const finalized = finalizeShareResponse(rawResponseBody, shareCampaign, sharePlatform);
      return finalized ?? json({ error: "upstream_error", message: "The writer returned an invalid post." }, 502);
    }

    const responseBody = textBlocksOnly(rawResponseBody, anthropicResponse.ok);
    return new Response(responseBody, {
      status: anthropicResponse.status,
      headers: { "Content-Type": "application/json" },
    });
}

export default {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const deadline = Date.now() + REQUEST_BUDGET_MS;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        handleRequest(request, env, deadline),
        new Promise<Response>(resolve => {
          timer = setTimeout(() => resolve(json({ error: "timeout", message: "The request took too long. Try again." }, 504)), REQUEST_BUDGET_MS);
        }),
      ]);
    } finally { if (timer !== undefined) clearTimeout(timer); }
  },
};

/**
 * Apply campaign guardrails to a raw Anthropic response.
 *
 * Returns null when the body could not be understood, so the caller falls back
 * to passing the upstream response through untouched.
 */
function finalizeShareResponse(
  responseBody: string,
  campaign: SmartShareCampaign,
  platform: SmartSharePlatform,
): Response | null {
  let parsed: { content?: Array<{ type: string; text?: string }>; stop_reason?: string };
  try {
    parsed = JSON.parse(responseBody);
  } catch {
    return null;
  }

  if (!parsed || !Array.isArray(parsed.content) || !["end_turn", "stop_sequence"].includes(parsed.stop_reason ?? "")) return null;
  const raw = parsed.content.filter(part => part?.type === "text").map(part => typeof part.text === "string" ? part.text : "").join("\n");
  if (typeof raw !== "string") return null;

  const finalized = finalizeShareCopy(raw, campaign, platform);
  if (finalized.blocked) {
    return json({ error: "campaign_blocked", message: finalized.blocked }, 422);
  }

  return json({
    ...parsed,
    content: [{ type: "text", text: finalized.text }],
  });
}

/**
 * Magic Copy's model call. Reuses the Smart Share prompt builder, so campaign
 * guardrails and platform voice are identical to the ones the web flow used —
 * there is one definition of how a share post gets written.
 */
function buildShareAnthropicBody(campaign: SmartShareCampaign, platform: SmartSharePlatform) {
  // Fresh seed per press, so pressing the hotkey again in another app (or the
  // same one) produces a genuinely different post rather than the same text.
  const prompt = buildSmartSharePrompt({
    campaign,
    platform,
    seed: Math.floor(Math.random() * 1_000_000),
    // The cursor could be in a subject field or a body; we cannot tell.
    omitSubject: true,
  });

  return {
    model: MODEL,
    max_tokens: SHARE_MAX_TOKENS,
    system: prompt.system,
    // Same low-latency profile as a normal paste (see buildPasteAnthropicBody).
    thinking: { type: "between_tools" },
    output_config: { effort: "low" },
    fallbacks: "default",
    // Non-zero temperature is what stops every sharer getting the same post.
    temperature: 1,
    messages: [{ role: "user", content: prompt.user }],
  };
}

function buildPasteAnthropicBody(pasteReq: PasteRequest) {
  return {
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: buildSystemPrompt(pasteReq),
    // Low-latency, no-thinking profile — the product is a hotkey, not a chat.
    // Sonnet 5.5 rejects {type: "disabled"}; "between_tools" is its
    // thinking-off setting (allowed at effort "high" or below).
    thinking: { type: "between_tools" },
    output_config: { effort: "low" },
    // On a cyber/frontier_llm refusal, Anthropic retries on Sonnet 5 server-side.
    fallbacks: "default",
    messages: [
      {
        role: "user",
        content: [
          {
            type: "image",
            source: {
              type: "base64",
              media_type: pasteReq.image.media_type,
              data: pasteReq.image.data,
            },
          },
          {
            type: "text",
            text: [
              pasteReq.app_name ? `Application: ${pasteReq.app_name}` : null,
              pasteReq.window_title ? `Window: ${pasteReq.window_title}` : null,
              "",
              "Generate the appropriate response based on what you see.",
            ]
              .filter((line) => line !== null)
              .join("\n"),
          },
        ],
      },
    ],
  };
}
