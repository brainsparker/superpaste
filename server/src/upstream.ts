/**
 * Upstream retry for the model call.
 *
 * The Worker talks to Anthropic with a bare fetch, so until now every
 * transient failure (529 overloaded_error, a 5xx blip, a dropped connection)
 * reached the Mac app as a failed paste. Anthropic's own SDKs retry those
 * twice by default; this module gives the proxy the same behaviour, bounded
 * by the request deadline so a retry never turns a fast failure into a hang.
 *
 * What is retried
 *   - 529 overloaded_error and 500/502/503/504: capacity on Anthropic's side.
 *   - 408 and 409: transient per Anthropic's SDK retry list.
 *   - 429 ONLY when it carries a short Retry-After. A 429 without one is a
 *     spend or acceleration limit on our organization; retrying that cannot
 *     succeed and only adds load.
 *   - A thrown fetch (connection reset, DNS, abort) when budget remains.
 *   Everything else (400, 401, 403, 404, 413, 422, 200) returns immediately.
 *
 * Backoff
 *   Equal jitter: half of the window is fixed, half random, so a fleet of
 *   Workers recovering from the same incident does not retry on one beat.
 *   Window doubles per retry and is capped. A Retry-After header, when short
 *   enough to honour, overrides the computed delay.
 *
 * Deadline
 *   One budget covers all attempts. Each attempt's timeout is the smaller of
 *   the per-attempt timeout and what is left, and no new attempt starts with
 *   less than minAttemptMs remaining. The caller therefore never waits longer
 *   than it did before this module existed.
 */

export interface RetryPolicy {
  /** Retries after the first attempt. 0 disables retry entirely. */
  maxRetries: number;
  /** Backoff window for the first retry, in ms. Doubles each retry. */
  baseDelayMs: number;
  /** Cap on the backoff window, in ms. */
  maxDelayMs: number;
  /** Longest Retry-After the loop will honour. Longer values end the loop. */
  maxRetryAfterMs: number;
  /** Total wall-clock budget for all attempts and delays, in ms. */
  deadlineMs: number;
  /** Timeout for a single attempt, in ms (clamped to remaining budget). */
  attemptTimeoutMs: number;
  /** Do not start an attempt with less than this much budget left, in ms. */
  minAttemptMs: number;
}

export const DEFAULT_RETRY_POLICY: RetryPolicy = {
  maxRetries: 2,
  baseDelayMs: 400,
  maxDelayMs: 2_000,
  maxRetryAfterMs: 5_000,
  deadlineMs: 60_000,
  attemptTimeoutMs: 60_000,
  minAttemptMs: 5_000,
};

/** Statuses retried without any further condition. */
export const RETRYABLE_STATUSES: ReadonlySet<number> = new Set([408, 409, 500, 502, 503, 504, 529]);

export interface UpstreamResult {
  /** The last response received, or null when every attempt threw. */
  response: Response | null;
  /** The error from the last attempt when it threw, else null. */
  error: unknown;
  /** Attempts made, including the first. Always at least 1. */
  attempts: number;
  /** Statuses of the responses that were retried, for logging. */
  retriedStatuses: number[];
}

export interface FetchWithRetryDeps {
  fetch?: typeof globalThis.fetch;
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
  now?: () => number;
  /** Called before each retry with what happened and how long we will wait. */
  onRetry?: (info: { attempt: number; status: number | null; delayMs: number; requestId: string | null }) => void;
}

/**
 * Parse a Retry-After header into milliseconds. Accepts delay-seconds and
 * HTTP-dates. Returns null when absent or unparseable.
 */
export function parseRetryAfterMs(value: string | null, now: number = Date.now()): number | null {
  if (value === null) return null;
  const trimmed = value.trim();
  if (trimmed === "") return null;
  if (/^\d+$/.test(trimmed)) return parseInt(trimmed, 10) * 1000;
  const date = Date.parse(trimmed);
  if (Number.isNaN(date)) return null;
  return Math.max(0, date - now);
}

/**
 * Decide whether a response should be retried under the policy.
 * Pure, so the rule is testable without a fetch.
 */
export function isRetryableResponse(response: Response, policy: RetryPolicy): boolean {
  if (RETRYABLE_STATUSES.has(response.status)) return true;
  if (response.status === 429) {
    const retryAfter = parseRetryAfterMs(response.headers.get("retry-after"));
    return retryAfter !== null && retryAfter <= policy.maxRetryAfterMs;
  }
  return false;
}

/**
 * Backoff for the Nth retry (1-based) under equal jitter. The random source
 * is injectable so tests are deterministic.
 */
export function backoffDelayMs(retry: number, policy: RetryPolicy, random: () => number = Math.random): number {
  const window = Math.min(policy.maxDelayMs, policy.baseDelayMs * 2 ** (retry - 1));
  const half = window / 2;
  return Math.round(half + random() * half);
}

/**
 * Run the upstream call with bounded retry. Never throws: a final thrown
 * attempt is reported in `error` with `response` null, so the caller keeps
 * its existing error mapping.
 */
export async function fetchWithRetry(
  input: string,
  init: Omit<RequestInit, "signal">,
  policy: RetryPolicy = DEFAULT_RETRY_POLICY,
  deps: FetchWithRetryDeps = {},
): Promise<UpstreamResult> {
  const doFetch = deps.fetch ?? globalThis.fetch;
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
  const random = deps.random ?? Math.random;
  const now = deps.now ?? Date.now;

  const started = now();
  const remaining = () => policy.deadlineMs - (now() - started);

  let response: Response | null = null;
  let error: unknown = null;
  let attempts = 0;
  const retriedStatuses: number[] = [];

  for (;;) {
    attempts += 1;
    const attemptTimeout = Math.max(1, Math.min(policy.attemptTimeoutMs, remaining()));
    try {
      response = await doFetch(input, { ...init, signal: AbortSignal.timeout(attemptTimeout) });
      error = null;
    } catch (err) {
      response = null;
      error = err;
    }

    const retriesLeft = policy.maxRetries - (attempts - 1);
    if (retriesLeft <= 0) break;

    let delayMs: number;
    if (response) {
      if (!isRetryableResponse(response, policy)) break;
      const retryAfter = parseRetryAfterMs(response.headers.get("retry-after"), now());
      delayMs = retryAfter !== null && retryAfter <= policy.maxRetryAfterMs
        ? retryAfter
        : backoffDelayMs(attempts, policy, random);
    } else {
      // A thrown fetch. Connection errors fail fast and are worth one more
      // try; a timeout has already spent the budget and falls out below.
      delayMs = backoffDelayMs(attempts, policy, random);
    }

    if (remaining() - delayMs < policy.minAttemptMs) break;

    const status = response?.status ?? null;
    if (status !== null) retriedStatuses.push(status);
    deps.onRetry?.({
      attempt: attempts,
      status,
      delayMs,
      requestId: response?.headers.get("request-id") ?? null,
    });
    // Drain the body we are discarding so the connection can be reused.
    if (response) await response.body?.cancel().catch(() => {});
    await sleep(delayMs);
  }

  return { response, error, attempts, retriedStatuses };
}

/**
 * Read the retry policy from Worker vars. Unset or unparseable values keep
 * the defaults, so a typo in wrangler.toml cannot disable the model call.
 */
export function retryPolicyFromEnv(
  env: { UPSTREAM_MAX_RETRIES?: string; UPSTREAM_RETRY_BASE_MS?: string },
  base: RetryPolicy = DEFAULT_RETRY_POLICY,
): RetryPolicy {
  const policy = { ...base };
  const maxRetries = parseInt(env.UPSTREAM_MAX_RETRIES ?? "", 10);
  if (Number.isInteger(maxRetries) && maxRetries >= 0 && maxRetries <= 5) policy.maxRetries = maxRetries;
  const baseDelay = parseInt(env.UPSTREAM_RETRY_BASE_MS ?? "", 10);
  if (Number.isInteger(baseDelay) && baseDelay >= 0 && baseDelay <= 10_000) policy.baseDelayMs = baseDelay;
  return policy;
}
