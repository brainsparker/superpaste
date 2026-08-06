/**
 * Smart Share Links — campaign schema and validation.
 *
 * Campaign data arrives from a URL that anyone can hand-edit, so everything
 * here treats its input as hostile: no throwing on bad shapes, hard length
 * ceilings on every field, and no field is ever trusted to be a string just
 * because the type says so.
 *
 * This module knows nothing about HTTP, prompts, or rendering. Parsing and
 * validation stay separate from generation on purpose (see ./prompt.ts).
 */

export type SmartSharePlatform =
  | "linkedin"
  | "x"
  | "threads"
  | "bluesky"
  | "facebook"
  | "reddit"
  | "slack"
  | "email"
  | "generic";

export const SMART_SHARE_PLATFORMS: readonly SmartSharePlatform[] = [
  "linkedin",
  "x",
  "threads",
  "bluesky",
  "facebook",
  "reddit",
  "slack",
  "email",
  "generic",
];

export interface SmartShareCampaign {
  id: string;
  name: string;
  intent: string;
  requiredUrl?: string;
  requiredFacts: string[];
  hashtags?: string[];
  tone?: string;
  prohibitedClaims?: string[];
  supportedPlatforms: SmartSharePlatform[];
  expiresAt?: string;
  createdAt: string;
  version: number;
}

/** A campaign before it has an id or a creation timestamp. */
export type SmartShareCampaignDraft = Omit<SmartShareCampaign, "id" | "createdAt">;

/** Current schema version. Bumped only on a breaking field change. */
export const SMART_SHARE_SCHEMA_VERSION = 1;

/**
 * Field limits. These are the security boundary, not a UI nicety: they bound
 * how much attacker-controlled text can reach a model prompt, and they keep
 * encoded links to a sane size.
 */
export const LIMITS = {
  name: 80,
  intent: 600,
  url: 500,
  fact: 200,
  facts: 8,
  hashtag: 40,
  hashtags: 6,
  tone: 60,
  prohibitedClaim: 160,
  prohibitedClaims: 10,
  /** Ceiling on the decoded JSON of a whole campaign. */
  encodedPayloadBytes: 4096,
  /**
   * Ceiling on `id`. Generous because the local provider's id IS the encoded
   * campaign token, which is base64 of up to `encodedPayloadBytes` (~4/3
   * expansion) plus a format prefix. A tighter limit would silently truncate
   * every real link into an undecodable id.
   */
  id: Math.ceil((4096 * 4) / 3) + 32,
} as const;

export type SmartShareErrorCode =
  | "invalid_link"
  | "invalid_campaign"
  | "campaign_expired"
  | "unsupported_platform"
  | "payload_too_large";

/** Error carrying a stable machine-readable code for the client to branch on. */
export class SmartShareError extends Error {
  readonly code: SmartShareErrorCode;
  /** Per-field detail, safe to show the user. Never includes raw payloads. */
  readonly details: string[];

  constructor(code: SmartShareErrorCode, message: string, details: string[] = []) {
    super(message);
    this.name = "SmartShareError";
    this.code = code;
    this.details = details;
  }
}

export type ParseResult<T> = { ok: true; value: T } | { ok: false; errors: string[] };

// --- Sanitizing helpers ---

/**
 * Strip control characters. These are invisible in a UI but survive into a
 * prompt, which makes them the obvious way to smuggle framing past a reviewer
 * who is eyeballing the campaign disclosure panel.
 */
function stripControlChars(value: string): string {
  let out = "";
  for (const char of value) {
    const code = char.codePointAt(0)!;
    // Allow \n and \t through; callers decide whether to collapse them.
    if (code === 0x0a || code === 0x09) {
      out += char;
      continue;
    }
    if (code < 0x20 || code === 0x7f) continue;
    // Bidi overrides and zero-width joiners: pure display trickery here.
    if (code >= 0x202a && code <= 0x202e) continue;
    if (code >= 0x2066 && code <= 0x2069) continue;
    if (code === 0x200b || code === 0x200e || code === 0x200f || code === 0xfeff) continue;
    out += char;
  }
  return out;
}

/** Single-line field: control chars out, all whitespace runs collapsed. */
function cleanLine(value: string, max: number): string {
  return stripControlChars(value).replace(/\s+/g, " ").trim().slice(0, max);
}

/** Multi-line field: keeps paragraph breaks, caps runs of blank lines. */
function cleanBlock(value: string, max: number): string {
  return stripControlChars(value)
    .replace(/\r/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, max);
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Validate a campaign's required URL.
 *
 * Only http and https. Anything else — `javascript:`, `data:`, `file:` — is a
 * link the share page would happily render into an anchor, so it is rejected
 * at the schema boundary rather than at render time.
 */
export function validateCampaignUrl(raw: string): ParseResult<string> {
  const trimmed = cleanLine(raw, LIMITS.url + 1);
  if (trimmed.length === 0) return { ok: false, errors: ["requiredUrl must not be empty"] };
  if (trimmed.length > LIMITS.url) {
    return { ok: false, errors: [`requiredUrl must be ${LIMITS.url} characters or fewer`] };
  }

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return { ok: false, errors: ["requiredUrl must be a valid absolute URL"] };
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return { ok: false, errors: ["requiredUrl must use http or https"] };
  }
  if (url.username !== "" || url.password !== "") {
    return { ok: false, errors: ["requiredUrl must not contain credentials"] };
  }
  if (url.hostname === "") {
    return { ok: false, errors: ["requiredUrl must include a hostname"] };
  }

  return { ok: true, value: url.toString() };
}

/** Normalize a hashtag to bare alphanumerics: `#Launch Day!` -> `LaunchDay`. */
export function normalizeHashtag(raw: string): string {
  return cleanLine(raw, LIMITS.hashtag + 1)
    .replace(/^#+/, "")
    .replace(/[^\p{L}\p{N}_]/gu, "")
    .slice(0, LIMITS.hashtag);
}

function readStringArray(
  raw: unknown,
  field: string,
  maxItems: number,
  maxLength: number,
  errors: string[],
): string[] {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) {
    errors.push(`${field} must be an array of strings`);
    return [];
  }
  if (raw.length > maxItems) {
    errors.push(`${field} must have ${maxItems} entries or fewer`);
    return [];
  }
  const out: string[] = [];
  for (const entry of raw) {
    if (typeof entry !== "string") {
      errors.push(`${field} must contain only strings`);
      return [];
    }
    const cleaned = cleanLine(entry, maxLength);
    if (cleaned.length > 0) out.push(cleaned);
  }
  // Dedupe case-insensitively; duplicate facts just waste prompt budget.
  const seen = new Set<string>();
  return out.filter((entry) => {
    const key = entry.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function isSmartSharePlatform(value: unknown): value is SmartSharePlatform {
  return typeof value === "string" && (SMART_SHARE_PLATFORMS as readonly string[]).includes(value);
}

/**
 * Validate an arbitrary object into a campaign draft (no id, no createdAt).
 * Used both by the create endpoint and by full-campaign parsing below.
 */
export function parseCampaignDraft(input: unknown): ParseResult<SmartShareCampaignDraft> {
  const errors: string[] = [];
  if (!isPlainObject(input)) {
    return { ok: false, errors: ["campaign must be a JSON object"] };
  }

  const name = typeof input.name === "string" ? cleanLine(input.name, LIMITS.name) : "";
  if (name.length === 0) errors.push("name is required");

  const intent = typeof input.intent === "string" ? cleanBlock(input.intent, LIMITS.intent) : "";
  if (intent.length === 0) errors.push("intent is required");

  let requiredUrl: string | undefined;
  if (input.requiredUrl !== undefined && input.requiredUrl !== null && input.requiredUrl !== "") {
    if (typeof input.requiredUrl !== "string") {
      errors.push("requiredUrl must be a string");
    } else {
      const parsed = validateCampaignUrl(input.requiredUrl);
      if (parsed.ok) requiredUrl = parsed.value;
      else errors.push(...parsed.errors);
    }
  }

  const requiredFacts = readStringArray(
    input.requiredFacts,
    "requiredFacts",
    LIMITS.facts,
    LIMITS.fact,
    errors,
  );

  const rawHashtags = readStringArray(
    input.hashtags,
    "hashtags",
    LIMITS.hashtags,
    LIMITS.hashtag,
    errors,
  );
  const hashtags = rawHashtags.map(normalizeHashtag).filter((tag) => tag.length > 0);

  const prohibitedClaims = readStringArray(
    input.prohibitedClaims,
    "prohibitedClaims",
    LIMITS.prohibitedClaims,
    LIMITS.prohibitedClaim,
    errors,
  );

  let tone: string | undefined;
  if (input.tone !== undefined && input.tone !== null && input.tone !== "") {
    if (typeof input.tone !== "string") errors.push("tone must be a string");
    else {
      const cleaned = cleanLine(input.tone, LIMITS.tone);
      if (cleaned.length > 0) tone = cleaned;
    }
  }

  let supportedPlatforms: SmartSharePlatform[] = [];
  if (!Array.isArray(input.supportedPlatforms)) {
    errors.push("supportedPlatforms must be an array");
  } else if (input.supportedPlatforms.length === 0) {
    errors.push("supportedPlatforms must list at least one platform");
  } else if (input.supportedPlatforms.length > SMART_SHARE_PLATFORMS.length) {
    errors.push("supportedPlatforms has too many entries");
  } else {
    const seen = new Set<SmartSharePlatform>();
    for (const entry of input.supportedPlatforms) {
      if (!isSmartSharePlatform(entry)) {
        errors.push(`unknown platform: ${typeof entry === "string" ? cleanLine(entry, 20) : "?"}`);
        continue;
      }
      seen.add(entry);
    }
    // Preserve the canonical order so the UI is stable regardless of input order.
    supportedPlatforms = SMART_SHARE_PLATFORMS.filter((platform) => seen.has(platform));
    if (supportedPlatforms.length === 0) errors.push("supportedPlatforms must list a known platform");
  }

  let expiresAt: string | undefined;
  if (input.expiresAt !== undefined && input.expiresAt !== null && input.expiresAt !== "") {
    if (typeof input.expiresAt !== "string") {
      errors.push("expiresAt must be an ISO 8601 string");
    } else {
      const parsed = Date.parse(input.expiresAt);
      if (Number.isNaN(parsed)) errors.push("expiresAt must be a valid ISO 8601 date");
      else expiresAt = new Date(parsed).toISOString();
    }
  }

  const version = input.version === undefined ? SMART_SHARE_SCHEMA_VERSION : input.version;
  if (typeof version !== "number" || !Number.isInteger(version) || version < 1) {
    errors.push("version must be a positive integer");
  } else if (version > SMART_SHARE_SCHEMA_VERSION) {
    // Forward-compat: a newer link may carry fields this build silently drops,
    // so refuse rather than generate from a half-understood campaign.
    errors.push(`unsupported campaign version ${version}; this build understands up to ${SMART_SHARE_SCHEMA_VERSION}`);
  }

  if (errors.length > 0) return { ok: false, errors };

  const draft: SmartShareCampaignDraft = {
    name,
    intent,
    requiredFacts,
    supportedPlatforms,
    version: version as number,
  };
  if (requiredUrl !== undefined) draft.requiredUrl = requiredUrl;
  if (hashtags.length > 0) draft.hashtags = hashtags;
  if (tone !== undefined) draft.tone = tone;
  if (prohibitedClaims.length > 0) draft.prohibitedClaims = prohibitedClaims;
  if (expiresAt !== undefined) draft.expiresAt = expiresAt;
  return { ok: true, value: draft };
}

/** Validate a complete campaign, including `id` and `createdAt`. */
export function parseCampaign(input: unknown): ParseResult<SmartShareCampaign> {
  const draft = parseCampaignDraft(input);
  if (!draft.ok) return draft;

  const raw = input as Record<string, unknown>;
  const errors: string[] = [];

  const id = typeof raw.id === "string" ? cleanLine(raw.id, LIMITS.id) : "";
  if (id.length === 0) errors.push("id is required");

  let createdAt = "";
  if (typeof raw.createdAt !== "string") {
    errors.push("createdAt is required");
  } else {
    const parsed = Date.parse(raw.createdAt);
    if (Number.isNaN(parsed)) errors.push("createdAt must be a valid ISO 8601 date");
    else createdAt = new Date(parsed).toISOString();
  }

  if (errors.length > 0) return { ok: false, errors };
  return { ok: true, value: { ...draft.value, id, createdAt } };
}

/** True when the campaign carries an expiry that has already passed. */
export function isCampaignExpired(campaign: SmartShareCampaign, now: number = Date.now()): boolean {
  if (!campaign.expiresAt) return false;
  const expiry = Date.parse(campaign.expiresAt);
  if (Number.isNaN(expiry)) return false;
  return expiry <= now;
}

/** Throwing wrapper used at trust boundaries where a code is more useful. */
export function assertUsableCampaign(
  campaign: SmartShareCampaign,
  platform: SmartSharePlatform,
  now: number = Date.now(),
): void {
  if (isCampaignExpired(campaign, now)) {
    throw new SmartShareError("campaign_expired", "This Smart Share link has expired.");
  }
  if (!campaign.supportedPlatforms.includes(platform)) {
    throw new SmartShareError(
      "unsupported_platform",
      `This campaign does not support ${platform}.`,
    );
  }
}
