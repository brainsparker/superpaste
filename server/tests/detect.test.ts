import { test } from "node:test";
import assert from "node:assert/strict";

import { detectPlatform, resolveTargetPlatform } from "../src/smartshare/detect.ts";
import { campaignFixture } from "./helpers.ts";

// --- Native apps (bundle id wins) ---

test("native apps are detected from their bundle id", () => {
  const cases: Array<[string, string]> = [
    ["com.tinyspeck.slackmacgap", "slack"],
    ["com.apple.mail", "email"],
    ["com.microsoft.Outlook", "email"],
    ["com.mimestream.Mimestream", "email"],
    ["com.reddit.reddit", "reddit"],
  ];
  for (const [bundleId, expected] of cases) {
    const result = detectPlatform({ bundleId });
    assert.equal(result.platform, expected, bundleId);
    assert.equal(result.source, "app");
  }
});

test("bundle id matching is case-insensitive and accepts helper suffixes", () => {
  assert.equal(detectPlatform({ bundleId: "COM.APPLE.MAIL" }).platform, "email");
  assert.equal(detectPlatform({ bundleId: "com.apple.mail.helper" }).platform, "email");
});

test("a bundle id that merely starts with the same letters is not matched", () => {
  // Guards against a naive startsWith: this must not be treated as Apple Mail.
  const result = detectPlatform({ bundleId: "com.apple.mailboxes-unrelated" });
  assert.equal(result.platform, "generic");
});

test("a native app beats a stale window title", () => {
  const result = detectPlatform({
    bundleId: "com.tinyspeck.slackmacgap",
    windowTitle: "Something about LinkedIn",
  });
  assert.equal(result.platform, "slack");
  assert.equal(result.source, "app");
});

// --- Browser window titles ---

test("real browser window titles resolve to the right platform", () => {
  const cases: Array<[string, string]> = [
    ["(3) Feed | LinkedIn", "linkedin"],
    ["Messaging | LinkedIn", "linkedin"],
    ["Home / X", "x"],
    ["(12) Home / X", "x"],
    ["Notifications / X", "x"],
    ["jane on X: \"hello\" / X", "x"],
    ["Bluesky", "bluesky"],
    ["Threads", "threads"],
    ["Facebook", "facebook"],
    ["Reddit - Dive into anything", "reddit"],
    ["r/macapps", "reddit"],
    ["Slack | general | SuperPaste", "slack"],
    ["Inbox (241) - brian@you.com - Gmail", "email"],
    ["Mail - Outlook", "email"],
    ["Proton Mail", "email"],
  ];
  for (const [windowTitle, expected] of cases) {
    const result = detectPlatform({ bundleId: "com.google.Chrome", appName: "Google Chrome", windowTitle });
    assert.equal(result.platform, expected, `title: ${windowTitle}`);
    assert.equal(result.source, "window");
  }
});

test("legacy Twitter titles still resolve to X", () => {
  assert.equal(
    detectPlatform({ bundleId: "com.apple.Safari", windowTitle: "Home / Twitter" }).platform,
    "x",
  );
});

test("titles are matched regardless of which browser is in front", () => {
  for (const bundleId of [
    "com.apple.Safari",
    "company.thebrowser.Browser",
    "org.mozilla.firefox",
    "com.brave.Browser",
    "app.zen-browser.zen",
    "some.browser.nobody.has.heard.of",
  ]) {
    assert.equal(
      detectPlatform({ bundleId, windowTitle: "Feed | LinkedIn" }).platform,
      "linkedin",
      bundleId,
    );
  }
});

// --- Fallback ---

test("an unrecognized context falls back to generic rather than failing", () => {
  for (const input of [
    {},
    { bundleId: "com.apple.TextEdit" },
    { bundleId: "com.google.Chrome", windowTitle: "Some random blog post" },
    { windowTitle: "" },
    { windowTitle: "   " },
  ]) {
    const result = detectPlatform(input);
    assert.equal(result.platform, "generic", JSON.stringify(input));
    assert.equal(result.source, "fallback");
  }
});

test("a bare word that merely contains x does not become X", () => {
  // "Linux", "Xcode" and friends must not trip the narrow X pattern.
  for (const windowTitle of ["Linux kernel docs", "Xcode", "Excel — Budget", "Box"]) {
    assert.equal(
      detectPlatform({ bundleId: "com.google.Chrome", windowTitle }).platform,
      "generic",
      windowTitle,
    );
  }
});

// --- Resolving against what the campaign allows ---

test("a supported detected platform is used as-is", () => {
  const campaign = campaignFixture({ supportedPlatforms: ["linkedin", "x"] });
  const result = resolveTargetPlatform(campaign, "x");
  assert.equal(result.platform, "x");
  assert.equal(result.substituted, false);
});

test("an unsupported platform falls back to generic when the campaign allows it", () => {
  const campaign = campaignFixture({ supportedPlatforms: ["linkedin", "generic"] });
  const result = resolveTargetPlatform(campaign, "reddit");
  assert.equal(result.platform, "generic");
  assert.equal(result.substituted, true);
});

test("without generic, it falls back to the first supported platform", () => {
  const campaign = campaignFixture({ supportedPlatforms: ["slack", "linkedin"] });
  const result = resolveTargetPlatform(campaign, "reddit");
  // Canonical order puts linkedin before slack.
  assert.equal(result.platform, "linkedin");
  assert.equal(result.substituted, true);
});

test("Magic Copy always resolves to something writable", () => {
  // Whatever the detection, a campaign always yields a usable platform — the
  // hotkey must never dead-end because the user was in an unexpected app.
  const campaign = campaignFixture({ supportedPlatforms: ["threads"] });
  for (const detected of ["linkedin", "x", "email", "generic", "reddit"] as const) {
    const result = resolveTargetPlatform(campaign, detected);
    assert.ok(campaign.supportedPlatforms.includes(result.platform));
  }
});
