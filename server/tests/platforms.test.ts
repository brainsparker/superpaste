import { test } from "node:test";
import assert from "node:assert/strict";

import {
  PLATFORM_CONFIG,
  applyIntentUrl,
  buildDestinationUrl,
  platformDirectory,
} from "../src/smartshare/platforms.ts";
import { SMART_SHARE_PLATFORMS } from "../src/smartshare/schema.ts";

test("every platform in the union has a config entry keyed by its own id", () => {
  for (const platform of SMART_SHARE_PLATFORMS) {
    const config = PLATFORM_CONFIG[platform];
    assert.ok(config, `${platform} has no config`);
    assert.equal(config.id, platform);
    assert.ok(config.label.length > 0);
    assert.ok(config.guidance.length > 0);
    assert.ok(config.targetChars > 0);
  }
  assert.equal(Object.keys(PLATFORM_CONFIG).length, SMART_SHARE_PLATFORMS.length);
});

test("a platform offering an open action always has a URL template to open", () => {
  for (const platform of SMART_SHARE_PLATFORMS) {
    const config = PLATFORM_CONFIG[platform];
    if (config.openLabel) {
      assert.ok(config.intentUrl, `${platform} offers an open action with no intent URL`);
    }
  }
});

test("only platforms that truly prefill text are marked as such", () => {
  // LinkedIn and Facebook removed text prefill from their share endpoints;
  // claiming otherwise would silently drop the user's post.
  assert.equal(PLATFORM_CONFIG.linkedin.prefill, "none");
  assert.equal(PLATFORM_CONFIG.facebook.prefill, "url");
  for (const platform of ["x", "bluesky", "threads", "reddit", "email"] as const) {
    assert.equal(PLATFORM_CONFIG[platform].prefill, "text", `${platform} should prefill text`);
  }
});

test("a platform that cannot prefill text explains why", () => {
  for (const platform of SMART_SHARE_PLATFORMS) {
    const config = PLATFORM_CONFIG[platform];
    if (config.openLabel && config.prefill !== "text") {
      assert.ok(config.openNote, `${platform} needs an openNote explaining the limitation`);
    }
  }
});

// --- Template substitution ---

test("applyIntentUrl substitutes and URL-encodes each placeholder", () => {
  const url = applyIntentUrl(
    { template: "https://example.com/?t={text}&s={subject}", spacesAsPercent20: false },
    { text: "hello world & more", subject: "a/b" },
  );
  assert.equal(url, "https://example.com/?t=hello%20world%20%26%20more&s=a%2Fb");
});

test("applyIntentUrl returns null when a required {url} is missing", () => {
  const intent = { template: "https://example.com/?u={url}", spacesAsPercent20: false };
  assert.equal(applyIntentUrl(intent, {}), null);
  assert.equal(applyIntentUrl(intent, { url: "https://superpaste.ai/" }), "https://example.com/?u=https%3A%2F%2Fsuperpaste.ai%2F");
});

test("a template with no placeholders passes through unchanged", () => {
  const url = applyIntentUrl(
    { template: "https://www.linkedin.com/feed/?shareActive=true", spacesAsPercent20: false },
    { text: "ignored" },
  );
  assert.equal(url, "https://www.linkedin.com/feed/?shareActive=true");
});

// --- buildDestinationUrl ---

test("buildDestinationUrl produces the real intent URL per platform", () => {
  assert.ok(buildDestinationUrl("x", "hi")!.startsWith("https://x.com/intent/post?text=hi"));
  assert.ok(buildDestinationUrl("bluesky", "hi")!.startsWith("https://bsky.app/intent/compose?text="));
  assert.ok(buildDestinationUrl("threads", "hi")!.startsWith("https://www.threads.net/intent/post?text="));
});

test("email uses %20 for spaces, not +, so mailto bodies are not mangled", () => {
  const url = buildDestinationUrl("email", "hello there", undefined, "a subject")!;
  assert.ok(url.startsWith("mailto:?"));
  assert.equal(url.includes("+"), false);
  assert.ok(url.includes("hello%20there"));
  assert.ok(url.includes("subject=a%20subject"));
});

test("reddit carries both the title and the body", () => {
  const url = buildDestinationUrl("reddit", "body text", undefined, "the title")!;
  assert.ok(url.startsWith("https://www.reddit.com/submit?"));
  assert.ok(url.includes("title=the%20title"));
  assert.ok(url.includes("text=body%20text"));
});

test("facebook needs a campaign URL and yields nothing without one", () => {
  assert.equal(buildDestinationUrl("facebook", "text"), null);
  assert.ok(
    buildDestinationUrl("facebook", "text", "https://superpaste.ai/")!.includes(
      "u=https%3A%2F%2Fsuperpaste.ai%2F",
    ),
  );
});

test("platforms with no reliable share URL return null", () => {
  assert.equal(buildDestinationUrl("slack", "text"), null);
  assert.equal(buildDestinationUrl("generic", "text"), null);
});

test("buildDestinationUrl trims surrounding whitespace from the post", () => {
  const url = buildDestinationUrl("x", "  hi  ")!;
  assert.ok(url.endsWith("text=hi"));
});

// --- Directory ---

test("the platform directory publishes what the UI needs and withholds prompt wording", () => {
  const directory = platformDirectory();
  assert.equal(directory.length, SMART_SHARE_PLATFORMS.length);

  for (const entry of directory) {
    assert.equal("guidance" in entry, false, `${entry.id} leaked prompt guidance to the client`);
    assert.ok("intentUrl" in entry, `${entry.id} must publish its intent URL template`);
    assert.ok("maxChars" in entry);
    assert.ok("prefill" in entry);
  }
});
