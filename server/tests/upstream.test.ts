/**
 * Unit tests for the upstream retry loop (src/upstream.ts).
 *
 * The loop is driven with a scripted fetch, a recording sleep, a fixed random
 * source, and a fake clock, so every test is deterministic and finishes in
 * milliseconds. Worker-level behaviour (what the app actually receives) is
 * covered in tests/retry.test.ts.
 */

import { test } from "vitest";
import assert from "node:assert/strict";

import {
  DEFAULT_RETRY_POLICY,
  backoffDelayMs,
  fetchWithRetry,
  isRetryableResponse,
  parseRetryAfterMs,
  retryPolicyFromEnv,
  type RetryPolicy,
} from "../src/upstream.ts";

// --- Harness ---------------------------------------------------------------

type Step = { status: number; headers?: Record<string, string> } | { throws: Error };

/** A fetch that plays back a script of responses and records each call. */
function scriptedFetch(steps: Step[]) {
  const calls: Array<{ signal: AbortSignal | null | undefined }> = [];
  const fetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    calls.push({ signal: init?.signal });
    const step = steps[calls.length - 1] ?? steps[steps.length - 1]!;
    if ("throws" in step) throw step.throws;
    return new Response(JSON.stringify({ step: calls.length }), { status: step.status, headers: step.headers });
  }) as typeof globalThis.fetch;
  return { fetch, calls };
}

function harness(steps: Step[], clockAdvancePerCallMs = 0) {
  const scripted = scriptedFetch(steps);
  const sleeps: number[] = [];
  let clock = 1_000_000;
  const deps = {
    fetch: (async (input: string | URL | Request, init?: RequestInit) => {
      clock += clockAdvancePerCallMs;
      return scripted.fetch(input, init);
    }) as typeof globalThis.fetch,
    sleep: async (ms: number) => {
      sleeps.push(ms);
      clock += ms;
    },
    random: () => 0.5,
    now: () => clock,
  };
  return { deps, sleeps, calls: scripted.calls };
}

const FAST: RetryPolicy = { ...DEFAULT_RETRY_POLICY, baseDelayMs: 400, maxDelayMs: 2_000 };

// --- parseRetryAfterMs -----------------------------------------------------

test("parseRetryAfterMs handles delay-seconds, HTTP-dates, and junk", () => {
  assert.equal(parseRetryAfterMs(null), null);
  assert.equal(parseRetryAfterMs(""), null);
  assert.equal(parseRetryAfterMs("2"), 2000);
  assert.equal(parseRetryAfterMs(" 0 "), 0);
  assert.equal(parseRetryAfterMs("soon"), null);
  const now = Date.parse("2026-11-04T12:00:00Z");
  assert.equal(parseRetryAfterMs("Wed, 04 Nov 2026 12:00:03 GMT", now), 3000);
  // A date in the past means "now", never a negative wait.
  assert.equal(parseRetryAfterMs("Wed, 04 Nov 2026 11:59:00 GMT", now), 0);
});

// --- isRetryableResponse ---------------------------------------------------

test("capacity errors are retryable, request errors are not", () => {
  for (const status of [408, 409, 500, 502, 503, 504, 529]) {
    assert.equal(isRetryableResponse(new Response(null, { status }), FAST), true, `status ${status}`);
  }
  for (const status of [200, 400, 401, 403, 404, 413, 422]) {
    assert.equal(isRetryableResponse(new Response(null, { status }), FAST), false, `status ${status}`);
  }
});

test("a 429 is retried only when it carries a short Retry-After", () => {
  const withShort = new Response(null, { status: 429, headers: { "retry-after": "2" } });
  const withLong = new Response(null, { status: 429, headers: { "retry-after": "60" } });
  const without = new Response(null, { status: 429 });
  assert.equal(isRetryableResponse(withShort, FAST), true);
  assert.equal(isRetryableResponse(withLong, FAST), false, "a long wait is not worth holding the request for");
  assert.equal(isRetryableResponse(without, FAST), false, "no Retry-After means a spend or acceleration limit");
});

// --- backoffDelayMs --------------------------------------------------------

test("backoff uses equal jitter, doubles per retry, and respects the cap", () => {
  // random() = 0 gives the floor (half the window), random() = 1 the ceiling.
  assert.equal(backoffDelayMs(1, FAST, () => 0), 200);
  assert.equal(backoffDelayMs(1, FAST, () => 1), 400);
  assert.equal(backoffDelayMs(2, FAST, () => 0), 400);
  assert.equal(backoffDelayMs(2, FAST, () => 1), 800);
  // Retry 5 would want a 6400ms window; the cap holds it at 2000.
  assert.equal(backoffDelayMs(5, FAST, () => 1), 2000);
  assert.equal(backoffDelayMs(5, FAST, () => 0), 1000);
});

// --- fetchWithRetry --------------------------------------------------------

test("a 529 followed by a 200 returns the 200 after one jittered wait", async () => {
  const { deps, sleeps, calls } = harness([{ status: 529 }, { status: 200 }]);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response?.status, 200);
  assert.equal(result.attempts, 2);
  assert.deepEqual(result.retriedStatuses, [529]);
  assert.deepEqual(sleeps, [300], "retry 1 with random 0.5 sits in the middle of the 200..400ms window");
  assert.equal(calls.length, 2);
});

test("retries stop at maxRetries and return the last response", async () => {
  const { deps, sleeps } = harness([{ status: 529 }, { status: 529 }, { status: 529 }, { status: 200 }]);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response?.status, 529);
  assert.equal(result.attempts, 3, "first attempt plus two retries");
  assert.deepEqual(result.retriedStatuses, [529, 529]);
  assert.deepEqual(sleeps, [300, 600]);
});

test("a 400 is never retried", async () => {
  const { deps, sleeps, calls } = harness([{ status: 400 }, { status: 200 }]);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response?.status, 400);
  assert.equal(result.attempts, 1);
  assert.deepEqual(sleeps, []);
  assert.equal(calls.length, 1);
});

test("a 200 is returned immediately", async () => {
  const { deps, calls } = harness([{ status: 200 }]);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response?.status, 200);
  assert.equal(result.attempts, 1);
  assert.equal(calls.length, 1);
});

test("maxRetries 0 disables retry entirely", async () => {
  const { deps, calls } = harness([{ status: 529 }, { status: 200 }]);
  const result = await fetchWithRetry("https://x/", {}, { ...FAST, maxRetries: 0 }, deps);
  assert.equal(result.response?.status, 529);
  assert.equal(result.attempts, 1);
  assert.equal(calls.length, 1);
});

test("a thrown connection error is retried and the success is returned", async () => {
  const { deps, calls } = harness([{ throws: new TypeError("fetch failed") }, { status: 200 }]);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response?.status, 200);
  assert.equal(result.error, null);
  assert.equal(result.attempts, 2);
  assert.equal(calls.length, 2);
});

test("when every attempt throws, the error is reported and response is null", async () => {
  const boom = new TypeError("fetch failed");
  const { deps } = harness([{ throws: boom }]);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response, null);
  assert.equal(result.error, boom);
  assert.equal(result.attempts, 3);
});

test("a short Retry-After on a 429 overrides the computed backoff", async () => {
  const { deps, sleeps } = harness([{ status: 429, headers: { "retry-after": "1" } }, { status: 200 }]);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response?.status, 200);
  assert.deepEqual(sleeps, [1000]);
});

test("a 429 without Retry-After ends the loop at once", async () => {
  const { deps, sleeps } = harness([{ status: 429 }, { status: 200 }]);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response?.status, 429);
  assert.equal(result.attempts, 1);
  assert.deepEqual(sleeps, []);
});

test("no retry starts when the deadline would be crossed", async () => {
  // Each attempt eats 58s of a 60s budget; after the first 529 only 2s remain,
  // which is below minAttemptMs, so the loop returns the 529 without sleeping.
  const { deps, sleeps, calls } = harness([{ status: 529 }, { status: 200 }], 58_000);
  const result = await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(result.response?.status, 529);
  assert.equal(result.attempts, 1);
  assert.deepEqual(sleeps, []);
  assert.equal(calls.length, 1);
});

test("each attempt carries its own abort signal", async () => {
  const { deps, calls } = harness([{ status: 529 }, { status: 200 }]);
  await fetchWithRetry("https://x/", {}, FAST, deps);
  assert.equal(calls.length, 2);
  for (const call of calls) assert.ok(call.signal instanceof AbortSignal);
  assert.notEqual(calls[0]!.signal, calls[1]!.signal);
});

test("onRetry reports the attempt, status, delay, and request id", async () => {
  const seen: Array<{ attempt: number; status: number | null; delayMs: number; requestId: string | null }> = [];
  const { deps } = harness([
    { status: 529, headers: { "request-id": "req_abc" } },
    { throws: new TypeError("fetch failed") },
    { status: 200 },
  ]);
  await fetchWithRetry("https://x/", {}, FAST, { ...deps, onRetry: (info) => seen.push(info) });
  assert.deepEqual(seen, [
    { attempt: 1, status: 529, delayMs: 300, requestId: "req_abc" },
    { attempt: 2, status: null, delayMs: 600, requestId: null },
  ]);
});

// --- retryPolicyFromEnv ----------------------------------------------------

test("env vars override retries and base delay, bad values keep the defaults", () => {
  assert.equal(retryPolicyFromEnv({}).maxRetries, DEFAULT_RETRY_POLICY.maxRetries);
  assert.equal(retryPolicyFromEnv({ UPSTREAM_MAX_RETRIES: "0" }).maxRetries, 0);
  assert.equal(retryPolicyFromEnv({ UPSTREAM_MAX_RETRIES: "4" }).maxRetries, 4);
  assert.equal(retryPolicyFromEnv({ UPSTREAM_MAX_RETRIES: "99" }).maxRetries, DEFAULT_RETRY_POLICY.maxRetries, "above the ceiling");
  assert.equal(retryPolicyFromEnv({ UPSTREAM_MAX_RETRIES: "lots" }).maxRetries, DEFAULT_RETRY_POLICY.maxRetries);
  assert.equal(retryPolicyFromEnv({ UPSTREAM_RETRY_BASE_MS: "100" }).baseDelayMs, 100);
  assert.equal(retryPolicyFromEnv({ UPSTREAM_RETRY_BASE_MS: "-5" }).baseDelayMs, DEFAULT_RETRY_POLICY.baseDelayMs);
  // Other fields come from the base policy untouched.
  const custom = retryPolicyFromEnv({ UPSTREAM_MAX_RETRIES: "1" }, { ...DEFAULT_RETRY_POLICY, deadlineMs: 1234 });
  assert.equal(custom.deadlineMs, 1234);
  assert.equal(custom.maxRetries, 1);
});
