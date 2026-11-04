/**
 * Worker-level tests for upstream retry on /v1/messages.
 *
 * The Worker's default export is driven with stubbed KV, a stubbed
 * ExecutionContext, and a scripted global fetch, so these assert what the Mac
 * app actually receives: a 529 that clears on retry becomes a normal paste, a
 * 529 that does not clear becomes a clean 503 with Retry-After, quota is
 * charged once per request however many attempts it took, and request errors
 * are still passed through untouched.
 *
 * UPSTREAM_RETRY_BASE_MS is set to 0 so the real backoff path runs without
 * making the suite wait.
 */

import { test, afterEach } from "vitest";
import assert from "node:assert/strict";

import worker, { type Env } from "../src/index.ts";

// --- Harness ---------------------------------------------------------------

function fakeKV(initial: Record<string, string> = {}) {
  const store = new Map(Object.entries(initial));
  return {
    store,
    get: async (key: string) => store.get(key) ?? null,
    put: async (key: string, value: string) => void store.set(key, value),
  };
}

const allowLimiter = { limit: async () => ({ success: true }) };

function env(overrides: Partial<Env> = {}): Env & { SUPERPASTE_KV: ReturnType<typeof fakeKV> } {
  return {
    ANTHROPIC_API_KEY: "test-key",
    POLAR_ACCESS_TOKEN: "polar-token",
    POLAR_ORGANIZATION_ID: "org",
    SUPERPASTE_KV: fakeKV(),
    IP_LIMITER: allowLimiter,
    VALIDATE_LIMITER: allowLimiter,
    UPSTREAM_RETRY_BASE_MS: "0",
    ...overrides,
  } as unknown as Env & { SUPERPASTE_KV: ReturnType<typeof fakeKV> };
}

function fakeCtx() {
  const pending: Promise<unknown>[] = [];
  return {
    pending,
    ctx: {
      waitUntil: (p: Promise<unknown>) => void pending.push(p),
      passThroughOnException: () => {},
    },
  };
}

const PASTE = {
  image: { data: "aGVsbG8=", media_type: "image/jpeg" },
  app_name: "Mail",
  window_title: "Re: lunch",
};

async function callWorker(environment: Env, deviceId = "device-1") {
  const request = new Request("https://api.superpaste.ai/v1/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Device-ID": deviceId },
    body: JSON.stringify(PASTE),
  });
  const { ctx, pending } = fakeCtx();
  const response = await worker.fetch(request, environment, ctx as unknown as ExecutionContext);
  await Promise.all(pending);
  return response;
}

type Step = { status: number; body?: unknown; headers?: Record<string, string> } | { throws: Error };

const realFetch = globalThis.fetch;
let upstreamCalls = 0;

/** Script Anthropic's replies. The last step repeats if more calls arrive. */
function scriptAnthropic(steps: Step[]) {
  upstreamCalls = 0;
  globalThis.fetch = (async () => {
    const step = steps[Math.min(upstreamCalls, steps.length - 1)]!;
    upstreamCalls += 1;
    if ("throws" in step) throw step.throws;
    const body =
      step.body ??
      (step.status === 200
        ? { content: [{ type: "text", text: "Sounds good, see you at noon." }], stop_reason: "end_turn" }
        : { type: "error", error: { type: "overloaded_error", message: "Overloaded" } });
    return new Response(JSON.stringify(body), {
      status: step.status,
      headers: { "Content-Type": "application/json", ...step.headers },
    });
  }) as typeof globalThis.fetch;
}

const today = new Date().toISOString().slice(0, 10);

afterEach(() => {
  globalThis.fetch = realFetch;
});

// --- Behaviour the app sees -------------------------------------------------

test("a 529 that clears on retry is a normal paste", async () => {
  scriptAnthropic([{ status: 529 }, { status: 200 }]);
  const e = env();

  const response = await callWorker(e);

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-SuperPaste-Upstream-Attempts"), "2");
  const data = (await response.json()) as { content: Array<{ type: string; text: string }> };
  assert.equal(data.content[0]!.text, "Sounds good, see you at noon.");
  assert.equal(upstreamCalls, 2);
});

test("a 529 that never clears becomes a 503 upstream_overloaded with Retry-After", async () => {
  scriptAnthropic([{ status: 529 }]);
  const e = env();

  const response = await callWorker(e);

  assert.equal(response.status, 503);
  assert.equal(response.headers.get("Retry-After"), "5");
  assert.equal(response.headers.get("X-SuperPaste-Upstream-Attempts"), "3", "first attempt plus two retries");
  const data = (await response.json()) as { error: string; message: string };
  assert.equal(data.error, "upstream_overloaded");
  assert.match(data.message, /busy right now/);
  assert.equal(upstreamCalls, 3);
});

test("quota is charged once per request, not once per attempt", async () => {
  scriptAnthropic([{ status: 529 }, { status: 529 }, { status: 200 }]);
  const e = env();

  await callWorker(e, "device-q");

  assert.equal(upstreamCalls, 3);
  assert.equal(e.SUPERPASTE_KV.store.get(`device:device-q:usage:${today}`), "1");
  assert.equal(e.SUPERPASTE_KV.store.get(`global:trial:usage:${today}`), "1");
});

test("an exhausted 529 still counts against quota, as every upstream-reaching request does", async () => {
  scriptAnthropic([{ status: 529 }]);
  const e = env();

  const response = await callWorker(e, "device-x");

  assert.equal(response.status, 503);
  assert.equal(e.SUPERPASTE_KV.store.get(`device:device-x:usage:${today}`), "1");
});

test("a 500 blip followed by success is a normal paste", async () => {
  scriptAnthropic([{ status: 500, body: { type: "error", error: { type: "api_error", message: "Internal" } } }, { status: 200 }]);

  const response = await callWorker(env());

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-SuperPaste-Upstream-Attempts"), "2");
});

test("a dropped connection followed by success is a normal paste", async () => {
  scriptAnthropic([{ throws: new TypeError("fetch failed") }, { status: 200 }]);

  const response = await callWorker(env());

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-SuperPaste-Upstream-Attempts"), "2");
});

test("when every attempt throws, the app gets the existing 502 and no quota is charged", async () => {
  scriptAnthropic([{ throws: new TypeError("fetch failed") }]);
  const e = env();

  const response = await callWorker(e, "device-z");

  assert.equal(response.status, 502);
  assert.equal(response.headers.get("X-SuperPaste-Upstream-Attempts"), "3");
  const data = (await response.json()) as { error: string };
  assert.equal(data.error, "upstream_error");
  assert.equal(e.SUPERPASTE_KV.store.get(`device:device-z:usage:${today}`), undefined, "nothing reached Anthropic");
});

test("a 400 from Anthropic is passed through once, with no retry", async () => {
  const body = { type: "error", error: { type: "invalid_request_error", message: "bad image" } };
  scriptAnthropic([{ status: 400, body }, { status: 200 }]);

  const response = await callWorker(env());

  assert.equal(response.status, 400);
  assert.equal(response.headers.get("X-SuperPaste-Upstream-Attempts"), "1");
  assert.deepEqual(await response.json(), body);
  assert.equal(upstreamCalls, 1);
});

test("a 429 without Retry-After (a spend limit) is passed through, not retried", async () => {
  const body = { type: "error", error: { type: "rate_limit_error", message: "limit" } };
  scriptAnthropic([{ status: 429, body }, { status: 200 }]);

  const response = await callWorker(env());

  assert.equal(response.status, 429);
  assert.equal(upstreamCalls, 1);
});

test("a 429 with a short Retry-After is retried", async () => {
  const body = { type: "error", error: { type: "rate_limit_error", message: "slow down" } };
  scriptAnthropic([{ status: 429, body, headers: { "retry-after": "0" } }, { status: 200 }]);

  const response = await callWorker(env());

  assert.equal(response.status, 200);
  assert.equal(upstreamCalls, 2);
});

test("a straight success still reports one attempt", async () => {
  scriptAnthropic([{ status: 200 }]);

  const response = await callWorker(env());

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-SuperPaste-Upstream-Attempts"), "1");
});

test("UPSTREAM_MAX_RETRIES=0 restores single-attempt behaviour", async () => {
  scriptAnthropic([{ status: 529 }, { status: 200 }]);

  const response = await callWorker(env({ UPSTREAM_MAX_RETRIES: "0" }));

  assert.equal(response.status, 503, "the single 529 is still reported cleanly");
  assert.equal(response.headers.get("X-SuperPaste-Upstream-Attempts"), "1");
  assert.equal(upstreamCalls, 1);
});
