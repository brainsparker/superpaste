/**
 * Smart Share Links — detecting where the user is about to post.
 *
 * Magic Copy has no platform picker: the user copies a campaign link, puts their
 * cursor in a composer, and presses the hotkey. The platform is inferred from
 * the frontmost app and its window title, both of which the client already
 * sends.
 *
 * This lives server-side on purpose. Window titles change whenever a social
 * network reskins, and bundle ids appear as apps ship — keeping the heuristics
 * in the Worker means a detection fix ships without an app release, the same
 * reason the paste prompt lives here rather than in the client.
 *
 * Detection is a hint, never a gate: an unrecognized context resolves to
 * `generic` and still produces usable copy.
 */

import { SMART_SHARE_PLATFORMS, type SmartShareCampaign, type SmartSharePlatform } from "./schema.ts";

export interface DetectionInput {
  /** Frontmost app's bundle identifier, e.g. "com.tinyspeck.slackmacgap". */
  bundleId?: string;
  /** Frontmost app's localized name. Localized, so only a weak signal. */
  appName?: string;
  /** Frontmost window title — the strongest signal inside a browser. */
  windowTitle?: string;
}

export interface Detection {
  platform: SmartSharePlatform;
  /**
   * `app` — matched a native app's bundle id (most reliable).
   * `window` — matched the window title, typically a browser tab.
   * `fallback` — nothing matched; `generic` was assumed.
   */
  source: "app" | "window" | "fallback";
}

/**
 * Native apps keyed by bundle id prefix. Bundle ids beat app names because
 * `appName` arrives localized ("Mail" is "Courrier" in French).
 */
const NATIVE_APPS: ReadonlyArray<{ prefix: string; platform: SmartSharePlatform }> = [
  { prefix: "com.tinyspeck.slackmacgap", platform: "slack" },
  { prefix: "com.apple.mail", platform: "email" },
  { prefix: "com.microsoft.outlook", platform: "email" },
  { prefix: "com.readdle.smartemail", platform: "email" },
  { prefix: "it.bloop.airmail", platform: "email" },
  { prefix: "com.mimestream.mimestream", platform: "email" },
  { prefix: "com.superhuman.mail", platform: "email" },
  { prefix: "com.reddit.reddit", platform: "reddit" },
  { prefix: "com.facebook.archon", platform: "facebook" },
  { prefix: "maccatalyst.com.atebits.tweetie", platform: "x" },
];

/**
 * Window-title patterns, most specific first.
 *
 * Ordering matters: a Threads tab can mention "Instagram", and an X tab title
 * is just "Home / X", so the narrow patterns have to win before the loose ones
 * get a chance.
 */
const TITLE_PATTERNS: ReadonlyArray<{ pattern: RegExp; platform: SmartSharePlatform }> = [
  { pattern: /\blinkedin\b/i, platform: "linkedin" },
  { pattern: /\bbluesky\b|\bbsky\.app\b/i, platform: "bluesky" },
  { pattern: /\bthreads\b|threads\.(net|com)/i, platform: "threads" },
  { pattern: /\breddit\b|(^|\s|\/)r\//i, platform: "reddit" },
  { pattern: /\bslack\b/i, platform: "slack" },
  { pattern: /\bfacebook\b/i, platform: "facebook" },
  // Gmail, Outlook Web, Proton, Fastmail and friends.
  { pattern: /\bgmail\b|\binbox\b|\boutlook\b|\bproton\s*mail\b|\bfastmail\b|\bwebmail\b/i, platform: "email" },
  // X is last and split in two. Names that can be matched case-insensitively
  // go first; the bare-letter forms ("Home / X") must stay case-SENSITIVE, or
  // "Linux", "Xcode", and "Box" would all read as X.
  { pattern: /\btwitter\b|\bx\.com\b/i, platform: "x" },
  { pattern: /(^|[(\s\/])X\s*$|\/\s*X\b/, platform: "x" },
];

/**
 * Infer the destination platform. Never throws; unknown contexts yield
 * `generic` so Magic Copy degrades to neutral copy instead of failing.
 */
export function detectPlatform(input: DetectionInput): Detection {
  const bundleId = (input.bundleId ?? "").trim().toLowerCase();

  // 1. A native app is unambiguous — trust it over any window title.
  if (bundleId) {
    for (const app of NATIVE_APPS) {
      if (bundleId === app.prefix || bundleId.startsWith(`${app.prefix}.`)) {
        return { platform: app.platform, source: "app" };
      }
    }
  }

  // 2. Fall back to the window title. Checked for every app, not just known
  //    browsers: an Electron app or an unlisted browser still names the site in
  //    its title, and a browser allowlist would only add a way for detection to
  //    silently stop working when a new browser ships.
  const title = (input.windowTitle ?? "").trim();
  if (title.length > 0) {
    for (const entry of TITLE_PATTERNS) {
      if (entry.pattern.test(title)) {
        return { platform: entry.platform, source: "window" };
      }
    }
  }

  // 3. A browser on an unrecognized page, or an app we know nothing about.
  return { platform: "generic", source: "fallback" };
}

/**
 * Pick the platform to actually generate for.
 *
 * Detection can land on a platform the campaign author didn't enable. Rather
 * than refusing to write anything, fall back: `generic` if the campaign allows
 * it, otherwise the first supported platform in canonical order.
 */
export function resolveTargetPlatform(
  campaign: SmartShareCampaign,
  detected: SmartSharePlatform,
): { platform: SmartSharePlatform; substituted: boolean } {
  if (campaign.supportedPlatforms.includes(detected)) {
    return { platform: detected, substituted: false };
  }
  if (campaign.supportedPlatforms.includes("generic")) {
    return { platform: "generic", substituted: true };
  }
  const first = SMART_SHARE_PLATFORMS.find((platform) =>
    campaign.supportedPlatforms.includes(platform),
  );
  // Schema validation guarantees at least one supported platform.
  return { platform: first ?? "generic", substituted: true };
}
