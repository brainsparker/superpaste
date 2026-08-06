/**
 * Tests for the Smart Share HTTP surface: platform config, campaign creation,
 * and link resolution. None of these routes reaches a model, so no stubbing of
 * the network is needed — generation lives on /v1/messages (see magiccopy.test.ts).
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import { handleSmartShareRequest, type SmartShareEnv } from "../src/smartshare/routes.ts";

// --- Harness ---------------------------------------------------------------

function env(overrides: Partial<SmartShareEnv> = {}): SmartShareEnv {
  return { SMART_SHARE_BASE_URL: "https://superpaste.ai", ...overrides };
}

function req(
  path: string,
  options: { method?: string; body?: unknown; origin?: string; rawBody?: string } = {},
): Request {
  const headers: Record<string, string> = {};
  if (options.origin) headers.Origin = options.origin;
  let body: string | undefined;
  if (options.rawBody !== undefined) {
    body = options.rawBody;
    headers["Content-Type"] = "application/json";
  } else if (options.body !== undefined) {
    body = JSON.stringify(options.body);
    headers["Content-Type"] = "application/json";
  }
  return new Request(`https://api.superpaste.ai${path}`, {
    method: options.method ?? (body ? "POST" : "GET"),
    headers,
    body,
  });
}

async function call(request: Request, environment: SmartShareEnv = env()) {
  return handleSmartShareRequest(request, environment);
}

const VALID_DRAFT = {
  name: "Launch day",
  intent: "Tell people SuperPaste is free with your own API key.",
  requiredUrl: "https://superpaste.ai/",
  requiredFacts: ["Works on macOS 14 and later"],
  supportedPlatforms: ["linkedin", "x", "email"],
};

/** Create a campaign through the real endpoint and return its token. */
async function createToken(draft: unknown = VALID_DRAFT): Promise<string> {
  const response = await call(req("/v1/smart-share/campaigns", { body: draft }));
  assert.ok(response);
  assert.equal(response.status, 200);
  const data = (await response.json()) as { id: string };
  return data.id;
}

// --- Routing ---------------------------------------------------------------

test("non-Smart-Share paths return null so the caller keeps its own routing", async () => {
  assert.equal(await call(req("/v1/messages", { body: {} })), null);
  assert.equal(await call(req("/v1/validate-license", { body: {} })), null);
  assert.equal(await call(req("/")), null);
});

test("an unknown Smart Share route is a 404", async () => {
  const response = await call(req("/v1/smart-share/nope"));
  assert.equal(response?.status, 404);
});

test("wrong methods are rejected with 405", async () => {
  for (const [path, method] of [
    ["/v1/smart-share/platforms", "POST"],
    ["/v1/smart-share/campaigns", "GET"],
    ["/v1/smart-share/resolve", "GET"],
  ] as const) {
    const response = await call(req(path, { method }));
    assert.equal(response?.status, 405, `${method} ${path}`);
  }
});

// --- CORS ------------------------------------------------------------------

test("allowed origins are echoed and unknown origins are not", async () => {
  const allowed = await call(req("/v1/smart-share/platforms", { origin: "https://superpaste.ai" }));
  assert.equal(allowed?.headers.get("Access-Control-Allow-Origin"), "https://superpaste.ai");

  const denied = await call(req("/v1/smart-share/platforms", { origin: "https://evil.example" }));
  assert.equal(denied?.headers.get("Access-Control-Allow-Origin"), null);
  // The response itself still succeeds; the browser is what enforces CORS.
  assert.equal(denied?.status, 200);
});

test("preflight requests get a 204 with the CORS headers", async () => {
  const response = await call(
    req("/v1/smart-share/resolve", { method: "OPTIONS", origin: "https://superpaste.ai" }),
  );
  assert.equal(response?.status, 204);
  assert.equal(response?.headers.get("Access-Control-Allow-Origin"), "https://superpaste.ai");
  assert.match(response?.headers.get("Access-Control-Allow-Methods") ?? "", /POST/);
});

// --- GET /platforms --------------------------------------------------------

test("the platform directory lists every platform with its limits", async () => {
  const response = await call(req("/v1/smart-share/platforms"));
  assert.equal(response?.status, 200);
  const data = (await response!.json()) as { platforms: Array<Record<string, unknown>> };

  assert.equal(data.platforms.length, 9);
  const x = data.platforms.find((entry) => entry.id === "x")!;
  assert.equal(x.maxChars, 280);
  assert.equal(x.prefill, "text");
  // LinkedIn cannot prefill text, and the directory must say so.
  const linkedin = data.platforms.find((entry) => entry.id === "linkedin")!;
  assert.equal(linkedin.prefill, "none");
  assert.ok(String(linkedin.openNote).length > 0);
});

// --- POST /campaigns -------------------------------------------------------

test("creating a campaign returns a share link with the payload in the fragment", async () => {
  const response = await call(req("/v1/smart-share/campaigns", { body: VALID_DRAFT }));
  assert.equal(response?.status, 200);
  const data = (await response!.json()) as { id: string; url: string };

  const url = new URL(data.url);
  assert.equal(url.origin, "https://superpaste.ai");
  assert.equal(url.pathname, "/share");
  assert.equal(url.search, "", "campaign data must never be in the query string");
  assert.ok(url.hash.includes(data.id));
});

test("an invalid campaign returns 400 with per-field details", async () => {
  const response = await call(
    req("/v1/smart-share/campaigns", {
      body: { ...VALID_DRAFT, name: "", requiredUrl: "javascript:alert(1)" },
    }),
  );
  assert.equal(response?.status, 400);
  const data = (await response!.json()) as { error: string; details: string[] };
  assert.equal(data.error, "invalid_campaign");
  assert.ok(data.details.length >= 2);
});

test("a non-JSON body is rejected", async () => {
  const response = await call(req("/v1/smart-share/campaigns", { rawBody: "not json" }));
  assert.equal(response?.status, 400);
});

test("an oversized body is rejected before it is parsed", async () => {
  const response = await call(
    req("/v1/smart-share/campaigns", { rawBody: JSON.stringify({ pad: "x".repeat(40_000) }) }),
  );
  assert.equal(response?.status, 400);
  const data = (await response!.json()) as { error: string };
  assert.equal(data.error, "payload_too_large");
});

// --- POST /resolve ---------------------------------------------------------

test("resolve returns the campaign and only its supported platforms", async () => {
  const token = await createToken();
  const response = await call(req("/v1/smart-share/resolve", { body: { campaign: token } }));
  assert.equal(response?.status, 200);

  const data = (await response!.json()) as {
    campaign: Record<string, unknown>;
    platforms: Array<{ id: string }>;
  };
  assert.equal(data.campaign.name, VALID_DRAFT.name);
  assert.equal(data.campaign.requiredUrl, VALID_DRAFT.requiredUrl);
  assert.deepEqual(
    data.platforms.map((entry) => entry.id),
    ["linkedin", "x", "email"],
  );
  // The token is not echoed back; the page already has it.
  assert.equal(data.campaign.id, undefined);
});

test("resolve accepts a full share URL, not just a bare token", async () => {
  const token = await createToken();
  const response = await call(
    req("/v1/smart-share/resolve", { body: { campaign: `https://superpaste.ai/share#c=${token}` } }),
  );
  assert.equal(response?.status, 200);
});

test("resolve rejects a missing or malformed campaign", async () => {
  assert.equal((await call(req("/v1/smart-share/resolve", { body: {} })))?.status, 400);
  assert.equal(
    (await call(req("/v1/smart-share/resolve", { body: { campaign: "v1.garbage!" } })))?.status,
    400,
  );
});

test("an expired campaign resolves to 410 Gone", async () => {
  const token = await createToken({
    ...VALID_DRAFT,
    expiresAt: "2020-01-01T00:00:00.000Z",
  });
  const response = await call(req("/v1/smart-share/resolve", { body: { campaign: token } }));
  assert.equal(response?.status, 410);
  const data = (await response!.json()) as { error: string };
  assert.equal(data.error, "campaign_expired");
});
