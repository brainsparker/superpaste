import { test } from "node:test";
import assert from "node:assert/strict";

import {
  LINK_FRAGMENT_KEY,
  MAX_TOKEN_LENGTH,
  buildShareLink,
  decodeCampaignToken,
  encodeCampaignToken,
  extractTokenFromLink,
} from "../src/smartshare/codec.ts";
import { SmartShareError } from "../src/smartshare/schema.ts";
import { campaignFixture } from "./helpers.ts";

// --- Round trip ---

test("a campaign survives an encode/decode round trip", () => {
  const campaign = campaignFixture();
  const decoded = decodeCampaignToken(encodeCampaignToken(campaign));

  assert.equal(decoded.ok, true);
  assert.ok(decoded.ok);
  assert.equal(decoded.value.name, campaign.name);
  assert.equal(decoded.value.intent, campaign.intent);
  assert.equal(decoded.value.requiredUrl, campaign.requiredUrl);
  assert.deepEqual(decoded.value.requiredFacts, campaign.requiredFacts);
  assert.deepEqual(decoded.value.hashtags, campaign.hashtags);
  assert.equal(decoded.value.tone, campaign.tone);
  assert.deepEqual(decoded.value.prohibitedClaims, campaign.prohibitedClaims);
  assert.deepEqual(decoded.value.supportedPlatforms, campaign.supportedPlatforms);
  assert.equal(decoded.value.createdAt, campaign.createdAt);
  assert.equal(decoded.value.version, campaign.version);
});

test("optional fields stay absent through a round trip", () => {
  const campaign = campaignFixture({
    requiredUrl: undefined,
    hashtags: undefined,
    tone: undefined,
    prohibitedClaims: undefined,
    expiresAt: undefined,
  });
  const decoded = decodeCampaignToken(encodeCampaignToken(campaign));
  assert.ok(decoded.ok);
  assert.equal(decoded.value.requiredUrl, undefined);
  assert.equal(decoded.value.hashtags, undefined);
  assert.equal(decoded.value.tone, undefined);
  assert.equal(decoded.value.prohibitedClaims, undefined);
  assert.equal(decoded.value.expiresAt, undefined);
});

test("non-ASCII campaign text round trips intact", () => {
  const campaign = campaignFixture({
    name: "Lancement 🚀 日本語",
    intent: "Dites aux gens que c'est gratuit — vraiment.",
    requiredFacts: ["Fonctionne sur macOS 14+"],
  });
  const decoded = decodeCampaignToken(encodeCampaignToken(campaign));
  assert.ok(decoded.ok);
  assert.equal(decoded.value.name, "Lancement 🚀 日本語");
  assert.equal(decoded.value.intent, "Dites aux gens que c'est gratuit — vraiment.");
});

test("the token is the identity, so an id inside the payload is ignored", () => {
  const token = encodeCampaignToken(campaignFixture({ id: "attacker-chosen-id" }));
  const decoded = decodeCampaignToken(token);
  assert.ok(decoded.ok);
  assert.equal(decoded.value.id, token);
  assert.notEqual(decoded.value.id, "attacker-chosen-id");
});

// --- Link shape: the payload must never reach the server in the URL ---

test("share links carry the payload in the fragment, never the query string", () => {
  const link = buildShareLink(campaignFixture(), "https://superpaste.ai");
  const url = new URL(link);

  assert.equal(url.pathname, "/share");
  assert.equal(url.search, "", "campaign data must not appear in the query string");
  assert.ok(url.hash.startsWith(`#${LINK_FRAGMENT_KEY}=`));

  const token = new URLSearchParams(url.hash.slice(1)).get(LINK_FRAGMENT_KEY);
  assert.ok(token);
  assert.equal(decodeCampaignToken(token).ok, true);
});

test("buildShareLink normalizes trailing slashes and strips existing query or fragment", () => {
  for (const base of [
    "https://superpaste.ai",
    "https://superpaste.ai/",
    "https://superpaste.ai///",
    "https://superpaste.ai/?utm=x",
    "https://superpaste.ai/#existing",
  ]) {
    const link = buildShareLink(campaignFixture(), base);
    assert.ok(link.startsWith("https://superpaste.ai/share#"), `unexpected link for base ${base}: ${link}`);
  }
});

// --- Hostile input ---

test("decoding rejects malformed tokens without throwing", () => {
  for (const input of [
    "",
    "   ",
    "not-a-token",
    "v2.abcdef",
    "v1.",
    "v1.!!!not-base64!!!",
    "v1." + Buffer.from("not json").toString("base64url"),
    "v1." + Buffer.from("[1,2,3]").toString("base64url"),
    "v1." + Buffer.from('"a string"').toString("base64url"),
    null,
    undefined,
    42,
    {},
  ]) {
    const result = decodeCampaignToken(input);
    assert.equal(result.ok, false, `expected ${JSON.stringify(input)} to be rejected`);
    assert.ok(!result.ok && result.errors.length > 0);
  }
});

test("decoding rejects a token whose base64 has been tampered with", () => {
  const token = encodeCampaignToken(campaignFixture());
  // Flip characters in the middle of the payload.
  const mangled = token.slice(0, 20) + "ZZZZ" + token.slice(24);
  const result = decodeCampaignToken(mangled);
  assert.equal(result.ok, false);
});

test("decoding runs full schema validation, so a hand-edited payload is caught", () => {
  const evil = {
    v: 1,
    n: "Launch",
    i: "Share this",
    f: ["fact"],
    p: ["x"],
    u: "javascript:alert(1)",
    c: "2026-01-01T00:00:00.000Z",
  };
  const token = "v1." + Buffer.from(JSON.stringify(evil)).toString("base64url");
  const result = decodeCampaignToken(token);
  assert.equal(result.ok, false, "a javascript: URL smuggled into the payload must be rejected");
});

test("decoding rejects a payload with an unknown platform", () => {
  const payload = {
    v: 1,
    n: "Launch",
    i: "Share this",
    f: [],
    p: ["myspace"],
    c: "2026-01-01T00:00:00.000Z",
  };
  const token = "v1." + Buffer.from(JSON.stringify(payload)).toString("base64url");
  assert.equal(decodeCampaignToken(token).ok, false);
});

test("decoding rejects an oversized token before parsing it", () => {
  const huge = "v1." + "A".repeat(MAX_TOKEN_LENGTH + 10);
  const result = decodeCampaignToken(huge);
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.errors[0]!.includes("too large"));
});

test("encoding refuses a campaign too large to fit in a link", () => {
  // Every field at its ceiling still fits; this forces the payload past it by
  // using the maximum number of maximum-length entries.
  const oversized = campaignFixture({
    intent: "x".repeat(600),
    requiredFacts: Array(8).fill("f".repeat(200)),
    prohibitedClaims: Array(10).fill("p".repeat(160)),
    hashtags: Array(6).fill("h".repeat(40)),
    name: "n".repeat(80),
    tone: "t".repeat(60),
    requiredUrl: "https://example.com/" + "q".repeat(470),
  });
  assert.throws(
    () => encodeCampaignToken(oversized),
    (err: unknown) => err instanceof SmartShareError && err.code === "payload_too_large",
  );
});

// --- Extracting a token from whatever the user pasted ---

test("extractTokenFromLink accepts a bare token, a full URL, and a raw fragment", () => {
  const token = encodeCampaignToken(campaignFixture());

  assert.equal(extractTokenFromLink(token), token);
  assert.equal(extractTokenFromLink(`  ${token}  `), token);
  assert.equal(extractTokenFromLink(`https://superpaste.ai/share#${LINK_FRAGMENT_KEY}=${token}`), token);
  assert.equal(extractTokenFromLink(`#${LINK_FRAGMENT_KEY}=${token}`), token);
  assert.equal(extractTokenFromLink(`${LINK_FRAGMENT_KEY}=${token}`), token);
});

test("extractTokenFromLink returns null when there is no token", () => {
  assert.equal(extractTokenFromLink(""), null);
  assert.equal(extractTokenFromLink("https://superpaste.ai/share"), null);
  assert.equal(extractTokenFromLink("https://superpaste.ai/share#other=1"), null);
});
