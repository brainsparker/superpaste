/**
 * Smart Share Links — analytics seam.
 *
 * SuperPaste ships with no telemetry and that is not changing: the README's
 * contributing rules say "No telemetry, ever," and the privacy policy promises
 * no analytics. So this file defines the shape of an analytics sink and a no-op
 * implementation, and nothing else.
 *
 * The seam exists so a campaign author running their OWN deployment can measure
 * their own campaign without that instrumentation ever being added to the
 * open-source client. Deliberate constraints on any future implementation:
 *
 * - No event may carry generated copy, campaign text, IP addresses, user agents,
 *   or any per-visitor identifier. The fields below are the whole budget.
 * - `campaignRef` must be a short hash of the campaign id, never the id itself
 *   (the id is the campaign payload).
 * - It stays opt-in and off by default. A self-hoster wires in a real
 *   implementation; the public build keeps the no-op.
 */

import type { SmartSharePlatform } from "./schema.ts";

export type SmartShareEvent =
  | { type: "link_opened"; campaignRef: string }
  | { type: "copy_generated"; campaignRef: string; platform: SmartSharePlatform; regeneration: boolean }
  | { type: "copy_failed"; campaignRef: string; platform: SmartSharePlatform; reason: string };

export interface SmartShareAnalytics {
  /** Record an event. Must never throw and never block the response. */
  record(event: SmartShareEvent): void;
}

/** The only implementation shipped in this repository. */
export class NoopSmartShareAnalytics implements SmartShareAnalytics {
  record(_event: SmartShareEvent): void {
    // Intentionally empty. See the module comment.
  }
}
