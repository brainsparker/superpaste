/**
 * SuperPaste API Proxy
 *
 * Handles trial enforcement, rate limiting, and license key validation
 * before proxying requests to Anthropic.
 *
 * Deploy: `cd server && npx wrangler deploy`
 * Secrets: ANTHROPIC_API_KEY, POLAR_ACCESS_TOKEN, POLAR_ORGANIZATION_ID
 * KV: SUPERPASTE_KV (create with `wrangler kv namespace create SUPERPASTE_KV`)
 */

interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  ANTHROPIC_API_KEY: string;
  POLAR_ACCESS_TOKEN: string;
  POLAR_ORGANIZATION_ID: string;
  SUPERPASTE_KV: KVNamespace;
  /** Per-IP burst limiters (Cloudflare Rate Limiting API, configured in wrangler.toml). */
  IP_LIMITER: RateLimiter;
  VALIDATE_LIMITER: RateLimiter;
  /** Total /v1/messages requests allowed per UTC day across all users (spend cap). */
  GLOBAL_DAILY_LIMIT?: string;
  /** Optional owner/developer bypass key. Set via `wrangler secret put OWNER_LICENSE_KEY`.
   *  When the presented license key equals this value, validation succeeds without
   *  calling Polar — used by the creator to exercise the app without a paid license.
   *  Kept out of source on purpose so the value never ships in the OSS repo. */
  OWNER_LICENSE_KEY?: string;
}

const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const TRIAL_DURATION_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const TRIAL_DAILY_LIMIT = 15;
const LICENSED_DAILY_LIMIT = 100;
const DEFAULT_GLOBAL_DAILY_LIMIT = 500;
const LICENSE_CACHE_TTL_SECONDS = 3600; // 1 hour

// --- Helper: JSON response ---
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// --- Helper: today's date as YYYY-MM-DD in UTC ---
function todayUTC(): string {
  return new Date().toISOString().slice(0, 10);
}

// --- Trial enforcement ---
async function enforceTrial(deviceId: string, env: Env): Promise<void> {
  const key = `device:${deviceId}:first_seen`;
  const existing = await env.SUPERPASTE_KV.get(key);

  if (!existing) {
    // First time this device is seen — start the trial clock
    await env.SUPERPASTE_KV.put(key, String(Date.now()));
    return;
  }

  const firstSeen = parseInt(existing, 10);
  if (Date.now() - firstSeen > TRIAL_DURATION_MS) {
    throw { status: 402, error: "trial_expired", message: "Your 7-day free trial has ended." };
  }
}

// --- Rate limit enforcement ---
async function enforceRateLimit(deviceId: string, limit: number, env: Env): Promise<void> {
  const usageKey = `device:${deviceId}:usage:${todayUTC()}`;
  const current = parseInt((await env.SUPERPASTE_KV.get(usageKey)) ?? "0", 10);

  if (current >= limit) {
    throw { status: 429, error: "rate_limited", message: "Daily limit reached. Resets at midnight UTC." };
  }

  // Increment with a 48-hour TTL so old keys self-clean
  await env.SUPERPASTE_KV.put(usageKey, String(current + 1), { expirationTtl: 48 * 3600 });
}

// --- Global spend cap ---
// Hard ceiling on total daily requests regardless of how many devices/IPs are
// involved — bounds worst-case Anthropic spend even under coordinated abuse.
async function enforceGlobalCap(env: Env): Promise<void> {
  const limit = parseInt(env.GLOBAL_DAILY_LIMIT ?? "", 10) || DEFAULT_GLOBAL_DAILY_LIMIT;
  const key = `global:usage:${todayUTC()}`;
  const current = parseInt((await env.SUPERPASTE_KV.get(key)) ?? "0", 10);

  if (current >= limit) {
    console.error(`Global daily cap reached (${limit} requests) — rejecting until midnight UTC`);
    throw { status: 429, error: "rate_limited", message: "Daily limit reached. Resets at midnight UTC." };
  }

  await env.SUPERPASTE_KV.put(key, String(current + 1), { expirationTtl: 48 * 3600 });
}

// --- License key validation (Polar.sh) ---
async function validateLicense(key: string, env: Env): Promise<boolean> {
  // Owner/developer bypass — value lives in a Cloudflare secret, never in source.
  if (env.OWNER_LICENSE_KEY && key === env.OWNER_LICENSE_KEY) {
    return true;
  }

  // Check KV cache first
  const cacheKey = `license_valid:${key}`;
  const cached = await env.SUPERPASTE_KV.get(cacheKey);
  if (cached !== null) {
    return cached === "1";
  }

  // Call Polar.sh validation API
  let isValid = false;
  try {
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
    });
    if (response.status === 401 || response.status === 403) {
      // Polar rejected OUR credentials, not the user's key. Fail open and skip
      // the cache so legitimate customers aren't locked out by a bad/rotated
      // POLAR_ACCESS_TOKEN, and the fix takes effect immediately.
      console.error(`Polar auth failed (${response.status}) — check POLAR_ACCESS_TOKEN / POLAR_ORGANIZATION_ID`);
      return true;
    }
    isValid = response.ok;
  } catch {
    // Network error — fail open to avoid blocking legitimate users
    return true;
  }

  // Cache result for 1 hour
  await env.SUPERPASTE_KV.put(cacheKey, isValid ? "1" : "0", {
    expirationTtl: LICENSE_CACHE_TTL_SECONDS,
  });

  return isValid;
}

// --- Main handler ---
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const clientIP = request.headers.get("CF-Connecting-IP") ?? "unknown";

    // --- Route: POST /v1/validate-license ---
    if (request.method === "POST" && url.pathname === "/v1/validate-license") {
      const { success } = await env.VALIDATE_LIMITER.limit({ key: clientIP });
      if (!success) {
        return json({ error: "too_many_requests", message: "Too many requests. Slow down." }, 429);
      }

      let body: { key?: string };
      try {
        body = await request.json() as { key?: string };
      } catch {
        return json({ error: "bad_request" }, 400);
      }

      if (!body.key) {
        return json({ valid: false, error: "missing_key" }, 400);
      }

      const isValid = await validateLicense(body.key, env);
      return json({ valid: isValid });
    }

    // --- Route: POST /v1/messages ---
    if (request.method !== "POST" || url.pathname !== "/v1/messages") {
      return new Response("Not Found", { status: 404 });
    }

    const deviceId = request.headers.get("X-Device-ID") ?? "unknown";
    const licenseKey = request.headers.get("X-License-Key");

    // Per-IP burst limit — X-Device-ID is client-controlled, so per-device
    // limits alone can be bypassed by rotating IDs. This can't.
    const { success } = await env.IP_LIMITER.limit({ key: clientIP });
    if (!success) {
      return json({ error: "too_many_requests", message: "Too many requests. Slow down." }, 429);
    }

    // Gate: license key or trial
    try {
      await enforceGlobalCap(env);
      if (licenseKey) {
        const isValid = await validateLicense(licenseKey, env);
        if (!isValid) {
          return json({ error: "license_invalid", message: "License key is not valid." }, 403);
        }
        await enforceRateLimit(deviceId, LICENSED_DAILY_LIMIT, env);
      } else {
        await enforceTrial(deviceId, env);
        await enforceRateLimit(deviceId, TRIAL_DAILY_LIMIT, env);
      }
    } catch (err: unknown) {
      const e = err as { status?: number; error?: string; message?: string };
      if (e.status) {
        return json({ error: e.error, message: e.message }, e.status);
      }
      throw err;
    }

    // Forward body to Anthropic
    let body: string;
    try {
      body = await request.text();
    } catch {
      return new Response("Bad Request", { status: 400 });
    }

    const anthropicResponse = await fetch(ANTHROPIC_MESSAGES_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body,
    });

    const responseBody = await anthropicResponse.text();
    return new Response(responseBody, {
      status: anthropicResponse.status,
      headers: { "Content-Type": "application/json" },
    });
  },
};
