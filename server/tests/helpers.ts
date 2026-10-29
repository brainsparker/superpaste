import type { SmartShareCampaign } from "../src/smartshare/schema.ts";

/** A valid, boring campaign. Tests override only the field under test. */
export function campaignFixture(overrides: Partial<SmartShareCampaign> = {}): SmartShareCampaign {
  return {
    id: "test-campaign",
    name: "SuperPaste 1.2 launch",
    intent: "Tell people SuperPaste now works without a subscription if they bring their own API key.",
    requiredUrl: "https://superpaste.ai/",
    requiredFacts: ["Works on macOS 14 and later", "Bring-your-own Anthropic key is free"],
    hashtags: ["macOS", "AI"],
    tone: "matter-of-fact",
    prohibitedClaims: ["fastest AI tool ever", "replaces your team"],
    // Canonical order (see SMART_SHARE_PLATFORMS) — parsing normalizes to it,
    // so a fixture in a different order would fail round-trip comparisons.
    supportedPlatforms: ["linkedin", "x", "slack", "email"],
    createdAt: "2026-01-01T00:00:00.000Z",
    version: 1,
    ...overrides,
  };
}
