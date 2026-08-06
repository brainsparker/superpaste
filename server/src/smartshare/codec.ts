/**
 * Smart Share Links — link encoding and parsing.
 *
 * A campaign is carried inside the link itself as a versioned base64url
 * payload. No campaign database, nothing to breach, and the feature works
 * without a hosted service — which is the point of shipping it local-first.
 *
 * The payload belongs in the URL *fragment* (`/share#c=...`), never the query
 * string. Fragments are not sent to the server in the request line, so
 * campaign contents stay out of access logs, out of `Referer` headers, and out
 * of any CDN's URL analytics. The share page reads the fragment client-side and
 * POSTs it to the generate endpoint in a request body.
 *
 * Never put an API key or private campaign data in one of these links: the
 * payload is encoded, not encrypted, and anyone holding the link can read it.
 */

import {
  LIMITS,
  SMART_SHARE_SCHEMA_VERSION,
  SmartShareError,
  type ParseResult,
  type SmartShareCampaign,
  type SmartShareCampaignDraft,
  parseCampaign,
} from "./schema.ts";

/** Prefix marking the token format, so a future format can coexist. */
const TOKEN_PREFIX = "v1.";

/** The fragment parameter the share page reads the token from. */
export const LINK_FRAGMENT_KEY = "c";

/**
 * Hard ceiling on a token. Bounds both the URL length and how much work a
 * hostile request can make the decoder do before it is rejected.
 * base64 costs ~4 characters per 3 bytes; leave room for the prefix.
 */
export const MAX_TOKEN_LENGTH = Math.ceil((LIMITS.encodedPayloadBytes * 4) / 3) + TOKEN_PREFIX.length + 8;

// --- base64url, UTF-8 safe, on both Workers and Node ---

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  // Chunked to avoid blowing the argument limit on large payloads.
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function toBase64Url(value: string): string {
  return value.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64Url(value: string): string {
  const restored = value.replace(/-/g, "+").replace(/_/g, "/");
  const padding = (4 - (restored.length % 4)) % 4;
  return restored + "=".repeat(padding);
}

// --- Encoding ---

/**
 * Encode a campaign into a link token.
 *
 * `id` is deliberately excluded from the payload: with an encoded link the
 * token *is* the identity, so storing an id inside it would be both redundant
 * and a second source of truth that could disagree with the token.
 */
export function encodeCampaignToken(campaign: SmartShareCampaign | SmartShareCampaignDraft): string {
  const { name, intent, requiredFacts, supportedPlatforms, version } = campaign;
  // Compact, stable key order. Only fields with content are emitted so the
  // token stays as short as the campaign allows.
  const payload: Record<string, unknown> = {
    v: version || SMART_SHARE_SCHEMA_VERSION,
    n: name,
    i: intent,
    f: requiredFacts,
    p: supportedPlatforms,
  };
  if (campaign.requiredUrl) payload.u = campaign.requiredUrl;
  if (campaign.hashtags?.length) payload.h = campaign.hashtags;
  if (campaign.tone) payload.t = campaign.tone;
  if (campaign.prohibitedClaims?.length) payload.x = campaign.prohibitedClaims;
  if (campaign.expiresAt) payload.e = campaign.expiresAt;
  payload.c = "createdAt" in campaign ? campaign.createdAt : new Date().toISOString();

  const json = JSON.stringify(payload);
  const bytes = new TextEncoder().encode(json);
  if (bytes.length > LIMITS.encodedPayloadBytes) {
    throw new SmartShareError(
      "payload_too_large",
      "This campaign is too large to fit in a share link. Trim the intent or required facts.",
    );
  }
  return TOKEN_PREFIX + toBase64Url(bytesToBase64(bytes));
}

/** Build the full shareable URL for a campaign. */
export function buildShareLink(
  campaign: SmartShareCampaign | SmartShareCampaignDraft,
  baseUrl: string,
): string {
  const token = encodeCampaignToken(campaign);
  // Fragment, not query — see the module comment.
  return `${baseUrl.replace(/[#?].*$/, "").replace(/\/+$/, "")}/share#${LINK_FRAGMENT_KEY}=${token}`;
}

// --- Decoding ---

/**
 * Decode a link token back into a validated campaign.
 *
 * Every failure path returns errors rather than throwing, because this runs on
 * whatever a stranger pasted into the address bar. Size is checked before
 * `JSON.parse` so an oversized payload costs nothing to reject.
 */
export function decodeCampaignToken(token: unknown): ParseResult<SmartShareCampaign> {
  if (typeof token !== "string") return { ok: false, errors: ["link payload must be a string"] };
  const trimmed = token.trim();
  if (trimmed.length === 0) return { ok: false, errors: ["link payload is empty"] };
  if (trimmed.length > MAX_TOKEN_LENGTH) return { ok: false, errors: ["link payload is too large"] };
  if (!trimmed.startsWith(TOKEN_PREFIX)) {
    return { ok: false, errors: ["unrecognized link format"] };
  }

  const encoded = trimmed.slice(TOKEN_PREFIX.length);
  if (!/^[A-Za-z0-9_-]+$/.test(encoded)) {
    return { ok: false, errors: ["link payload is not valid base64url"] };
  }

  let json: string;
  try {
    const bytes = base64ToBytes(fromBase64Url(encoded));
    if (bytes.length > LIMITS.encodedPayloadBytes) {
      return { ok: false, errors: ["link payload is too large"] };
    }
    // `fatal` so mangled bytes fail loudly instead of decoding to U+FFFD soup.
    json = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    return { ok: false, errors: ["link payload could not be decoded"] };
  }

  let raw: unknown;
  try {
    raw = JSON.parse(json);
  } catch {
    return { ok: false, errors: ["link payload is not valid JSON"] };
  }
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return { ok: false, errors: ["link payload must be a JSON object"] };
  }

  const payload = raw as Record<string, unknown>;
  // Expand the compact keys, then hand the result to the same validator the
  // create endpoint uses. Validation lives in exactly one place.
  const expanded: Record<string, unknown> = {
    // The token is the identity: derive the id from it rather than trusting a
    // value inside the payload.
    id: trimmed,
    version: payload.v,
    name: payload.n,
    intent: payload.i,
    requiredFacts: payload.f,
    supportedPlatforms: payload.p,
    requiredUrl: payload.u,
    hashtags: payload.h,
    tone: payload.t,
    prohibitedClaims: payload.x,
    expiresAt: payload.e,
    createdAt: payload.c,
  };

  return parseCampaign(expanded);
}

/**
 * Pull a token out of anything the user might paste: a bare token, a full
 * share URL, or a fragment string. Tolerant on input, strict on validation.
 */
export function extractTokenFromLink(input: string): string | null {
  const trimmed = input.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.startsWith(TOKEN_PREFIX)) return trimmed;

  const fragment = trimmed.includes("#") ? trimmed.slice(trimmed.indexOf("#") + 1) : trimmed;
  const params = new URLSearchParams(fragment);
  const token = params.get(LINK_FRAGMENT_KEY);
  return token && token.length > 0 ? token : null;
}
