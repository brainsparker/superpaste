/**
 * Smart Share Links — platform configuration.
 *
 * Every platform-specific fact lives here: voice guidance, length targets,
 * whether hashtags belong, and whether the platform has a share URL that
 * actually prefills text. The UI reads this over HTTP (`GET
 * /v1/smart-share/platforms`) so no platform rule is duplicated in page code.
 *
 * Add a platform by adding an entry here plus a union member in ./schema.ts.
 */

import type { SmartSharePlatform } from "./schema.ts";

/**
 * How much of a post a platform's share URL can prefill.
 *
 * Being honest about this matters: LinkedIn and Facebook removed text prefill
 * from their share endpoints years ago, so promising "Open LinkedIn" with the
 * copy filled in would just lose the user's text. `none` and `url` both mean
 * "copy first, then open".
 */
export type SharePrefill = "text" | "url" | "none";

/**
 * Template for a platform's share URL.
 *
 * Kept as a template rather than a function so it can be handed to the browser
 * in the platform directory. The share page must rebuild the URL from whatever
 * the user has edited in the textarea, and a template means both sides share one
 * definition instead of the page reimplementing per-platform URL building.
 *
 * Placeholders are substituted URL-encoded: `{text}`, `{subject}`, `{url}`.
 */
export interface IntentUrl {
  template: string;
  /**
   * `mailto:` must encode spaces as %20; `+` is only a space inside
   * application/x-www-form-urlencoded query strings.
   */
  spacesAsPercent20: boolean;
}

export interface PlatformConfig {
  id: SmartSharePlatform;
  /** Human label for the UI. */
  label: string;
  /** Length the model should aim for, in characters. */
  targetChars: number;
  /**
   * Hard ceiling the platform itself enforces, if any. Generated copy over this
   * is reported as a warning rather than silently truncated.
   */
  maxChars: number | null;
  /** Whether hashtags read as native here. */
  allowsHashtags: boolean;
  /** Whether the output needs a subject line (email). */
  hasSubject: boolean;
  /** Voice and formatting guidance injected into the prompt. */
  guidance: string;
  /** How much a share URL can prefill, if a share URL exists at all. */
  prefill: SharePrefill;
  /** The share URL template, or null when the platform has no reliable one. */
  intentUrl: IntentUrl | null;
  /** Shown next to the open action so the user knows what to expect. */
  openLabel: string | null;
  /** Note explaining what happens on open, when it is not a full prefill. */
  openNote: string | null;
}

export const PLATFORM_CONFIG: Record<SmartSharePlatform, PlatformConfig> = {
  linkedin: {
    id: "linkedin",
    label: "LinkedIn",
    targetChars: 700,
    maxChars: 3000,
    allowsHashtags: true,
    hasSubject: false,
    guidance: [
      "Professional but written in the first person, like a real practitioner posting on their own account.",
      "Open with a concrete hook, not a greeting and not a question cliche.",
      "Use short paragraphs separated by blank lines so it is readable in the feed. No markdown, no bullet characters.",
      "Three to six short paragraphs. Put the link on its own line near the end.",
      "At most two or three hashtags, on the final line.",
    ].join(" "),
    prefill: "none",
    intentUrl: { template: "https://www.linkedin.com/feed/?shareActive=true", spacesAsPercent20: false },
    openLabel: "Open LinkedIn",
    openNote: "LinkedIn cannot prefill post text. Copy first, then paste into the composer.",
  },
  x: {
    id: "x",
    label: "X",
    targetChars: 240,
    maxChars: 280,
    allowsHashtags: true,
    hasSubject: false,
    guidance: [
      "One tight post under the character limit, including the link.",
      "Direct and specific. No throat-clearing, no hashtag pileup, at most one hashtag.",
      "A URL counts as roughly 23 characters regardless of its real length.",
      "Single paragraph, or two very short lines. No markdown.",
    ].join(" "),
    prefill: "text",
    intentUrl: { template: "https://x.com/intent/post?text={text}", spacesAsPercent20: false },
    openLabel: "Open X",
    openNote: null,
  },
  threads: {
    id: "threads",
    label: "Threads",
    targetChars: 320,
    maxChars: 500,
    allowsHashtags: false,
    hasSubject: false,
    guidance: [
      "Conversational and casual, like talking to people who already follow you.",
      "Lowercase openers and contractions are fine. Avoid marketing cadence entirely.",
      "One or two short paragraphs. Hashtags feel out of place here, so skip them.",
    ].join(" "),
    prefill: "text",
    intentUrl: { template: "https://www.threads.net/intent/post?text={text}", spacesAsPercent20: false },
    openLabel: "Open Threads",
    openNote: null,
  },
  bluesky: {
    id: "bluesky",
    label: "Bluesky",
    targetChars: 260,
    maxChars: 300,
    allowsHashtags: false,
    hasSubject: false,
    guidance: [
      "Short, plain-spoken, a little dry. The audience is technical and allergic to marketing voice.",
      "Stay under the character limit including the link. One paragraph. Skip hashtags.",
    ].join(" "),
    prefill: "text",
    intentUrl: { template: "https://bsky.app/intent/compose?text={text}", spacesAsPercent20: false },
    openLabel: "Open Bluesky",
    openNote: null,
  },
  facebook: {
    id: "facebook",
    label: "Facebook",
    targetChars: 400,
    maxChars: null,
    allowsHashtags: false,
    hasSubject: false,
    guidance: [
      "Warm and personal, written for friends and family rather than an industry audience.",
      "Explain why it matters in plain language. Assume no jargon and no shared context.",
      "One or two short paragraphs. Hashtags are unusual here, so skip them.",
    ].join(" "),
    prefill: "url",
    intentUrl: { template: "https://www.facebook.com/sharer/sharer.php?u={url}", spacesAsPercent20: false },
    openLabel: "Open Facebook",
    openNote: "Facebook only prefills the link. Copy the text first, then paste it into the post.",
  },
  reddit: {
    id: "reddit",
    label: "Reddit",
    targetChars: 600,
    maxChars: null,
    allowsHashtags: false,
    hasSubject: true,
    guidance: [
      "Transparent and community-aware. State plainly what this is and any connection the poster has to it.",
      "Never write it as an advertisement. Redditors punish promotional voice hard.",
      "Lead with the useful substance, then the link. Give people something to actually discuss.",
      "Provide a title line and a body. Never use hashtags.",
    ].join(" "),
    prefill: "text",
    intentUrl: { template: "https://www.reddit.com/submit?title={subject}&text={text}", spacesAsPercent20: false },
    openLabel: "Open Reddit",
    openNote: "Opens Reddit's submit page. Pick a subreddit before posting.",
  },
  slack: {
    id: "slack",
    label: "Slack",
    targetChars: 280,
    maxChars: null,
    allowsHashtags: false,
    hasSubject: false,
    guidance: [
      "A brief internal message to colleagues, as if posting in a team channel.",
      "Get to the point in the first line. Say why the channel should care and what to do with the link.",
      "Two to four sentences. No hashtags, no marketing voice, no emoji unless the tone calls for it.",
    ].join(" "),
    prefill: "none",
    intentUrl: null,
    openLabel: null,
    openNote: null,
  },
  email: {
    id: "email",
    label: "Email",
    targetChars: 700,
    maxChars: null,
    allowsHashtags: false,
    hasSubject: true,
    guidance: [
      "A short personal email, not a newsletter blast.",
      "Write a specific subject line that would survive a crowded inbox. Avoid all-caps and exclamation marks.",
      "Two or three short paragraphs, then the link. Plain text, no markdown, no signature block.",
    ].join(" "),
    prefill: "text",
    intentUrl: { template: "mailto:?subject={subject}&body={text}", spacesAsPercent20: true },
    openLabel: "Open email draft",
    openNote: null,
  },
  generic: {
    id: "generic",
    label: "Anywhere",
    targetChars: 400,
    maxChars: null,
    allowsHashtags: false,
    hasSubject: false,
    guidance: [
      "Neutral, reusable copy that reads well anywhere without being tuned to one platform.",
      "No platform-specific conventions, no hashtags, no markdown. Two short paragraphs at most.",
    ].join(" "),
    prefill: "none",
    intentUrl: null,
    openLabel: null,
    openNote: null,
  },
};

export function platformConfig(platform: SmartSharePlatform): PlatformConfig {
  return PLATFORM_CONFIG[platform];
}

/**
 * Substitute an intent-URL template.
 *
 * The share page runs the equivalent substitution on the same template, so this
 * stays the single definition of how each platform's URL is assembled. A
 * template needing `{url}` with no campaign URL available yields null rather
 * than a broken link.
 */
export function applyIntentUrl(
  intent: IntentUrl,
  values: { text?: string; subject?: string; url?: string },
): string | null {
  const encode = (value: string): string => {
    const encoded = encodeURIComponent(value);
    return intent.spacesAsPercent20 ? encoded.replace(/\+/g, "%20") : encoded;
  };

  let result = intent.template;
  for (const key of ["text", "subject", "url"] as const) {
    const placeholder = `{${key}}`;
    if (!result.includes(placeholder)) continue;
    const value = values[key];
    // A required value that is missing makes the whole URL useless.
    if (key === "url" && !value) return null;
    result = result.split(placeholder).join(encode(value ?? ""));
  }
  return result;
}

/**
 * Build the destination URL for a platform, or null when no reliable one exists.
 * `subject` is the Reddit title / email subject.
 *
 * Only ever called with copy the user has already reviewed on the share page —
 * nothing here posts anything, it just opens a prefilled composer.
 */
export function buildDestinationUrl(
  platform: SmartSharePlatform,
  text: string,
  requiredUrl?: string,
  subject?: string,
): string | null {
  const intent = PLATFORM_CONFIG[platform].intentUrl;
  if (!intent) return null;
  return applyIntentUrl(intent, {
    text: text.trim(),
    subject: subject?.trim(),
    url: requiredUrl,
  });
}

/** Serializable view of the config for the browser UI. */
export function platformDirectory(): Array<
  Pick<
    PlatformConfig,
    "id"
    | "label"
    | "targetChars"
    | "maxChars"
    | "allowsHashtags"
    | "hasSubject"
    | "prefill"
    | "intentUrl"
    | "openLabel"
    | "openNote"
  >
> {
  // Deliberately omits `guidance`: prompt wording is server-owned and there is
  // no reason to publish it to every visitor.
  return Object.values(PLATFORM_CONFIG).map((config) => ({
    id: config.id,
    label: config.label,
    targetChars: config.targetChars,
    maxChars: config.maxChars,
    allowsHashtags: config.allowsHashtags,
    hasSubject: config.hasSubject,
    prefill: config.prefill,
    intentUrl: config.intentUrl,
    openLabel: config.openLabel,
    openNote: config.openNote,
  }));
}
