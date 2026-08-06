/**
 * Smart Share Links — text generation.
 *
 * The only place in the feature that talks to a model. Keeping the model client
 * here means prompt construction (./prompt.ts) stays a pure string function and
 * can be tested without stubbing the network.
 *
 * Like the paste endpoint, the Worker owns the model, the token ceiling, and
 * the prompt. Clients send a campaign and a platform, never model parameters.
 */

import { buildSmartSharePrompt, validateGeneratedCopy, type GeneratedCopy } from "./prompt.ts";
import type { SmartShareCampaign, SmartSharePlatform } from "./schema.ts";

const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const ANTHROPIC_TIMEOUT_MS = 30_000;

const MODEL = "claude-sonnet-5";
/** A social post is short. This bounds cost on an unauthenticated endpoint. */
const MAX_TOKENS = 1024;

export interface GenerateOptions {
  campaign: SmartShareCampaign;
  platform: SmartSharePlatform;
  seed: number;
  previousDrafts?: string[];
  apiKey: string;
}

export interface GenerateResult extends GeneratedCopy {
  platform: SmartSharePlatform;
  /** Which opening strategy produced this draft — shown in the UI. */
  angle: string;
  /** Echoed so the client can pass it back and avoid repeating a draft. */
  seed: number;
}

export class GenerationError extends Error {
  readonly status: number;
  constructor(message: string, status = 502) {
    super(message);
    this.name = "GenerationError";
    this.status = status;
  }
}

interface AnthropicResponseBody {
  content?: Array<{ type: string; text?: string }>;
  stop_reason?: string;
  error?: { message?: string };
}

export async function generateShareCopy(options: GenerateOptions): Promise<GenerateResult> {
  const { campaign, platform, seed, previousDrafts, apiKey } = options;
  const prompt = buildSmartSharePrompt({ campaign, platform, seed, previousDrafts });

  let response: Response;
  try {
    response = await fetch(ANTHROPIC_MESSAGES_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: prompt.system,
        // Same low-latency profile the paste path uses; this is a short post,
        // not a reasoning task, and the user is waiting on a web page.
        thinking: { type: "disabled" },
        output_config: { effort: "low" },
        // Non-zero temperature is what makes two visitors get different copy.
        temperature: 1,
        messages: [{ role: "user", content: prompt.user }],
      }),
      signal: AbortSignal.timeout(ANTHROPIC_TIMEOUT_MS),
    });
  } catch (err) {
    console.error("Smart Share generation request failed:", err);
    throw new GenerationError("The writing service didn't respond. Try again.");
  }

  if (!response.ok) {
    // Never surface the upstream body: it can echo prompt content.
    console.error(`Smart Share generation upstream status ${response.status}`);
    if (response.status === 429) {
      throw new GenerationError("The writing service is busy. Try again in a moment.", 429);
    }
    throw new GenerationError("Couldn't write the post. Try again.");
  }

  let body: AnthropicResponseBody;
  try {
    body = (await response.json()) as AnthropicResponseBody;
  } catch {
    throw new GenerationError("Couldn't read the generated post. Try again.");
  }

  if (body.error) {
    console.error("Smart Share generation returned an error object");
    throw new GenerationError("Couldn't write the post. Try again.");
  }

  const raw = body.content?.find((part) => part.type === "text")?.text?.trim();
  if (!raw) {
    throw new GenerationError("The writing service returned an empty post. Try again.");
  }

  const copy = validateGeneratedCopy(raw, campaign, platform);
  if (body.stop_reason === "max_tokens") {
    copy.warnings.push("This draft was cut off. Regenerate for a complete post.");
  }

  return {
    ...copy,
    platform,
    angle: prompt.angle.id,
    seed,
  };
}
