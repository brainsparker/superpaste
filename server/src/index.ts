/**
 * SuperPaste API Proxy
 *
 * Receives vision requests from the macOS app and forwards them to Anthropic.
 * The API key lives here — users never need to configure anything.
 *
 * Deploy: `cd server && npx wrangler deploy`
 * Set secret: `npx wrangler secret put ANTHROPIC_API_KEY`
 */

export interface Env {
  ANTHROPIC_API_KEY: string;
}

const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Only accept POST /v1/messages
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/messages") {
      return new Response("Not Found", { status: 404 });
    }

    // Forward the body as-is — the app sends a valid Anthropic request payload
    let body: string;
    try {
      body = await request.text();
    } catch {
      return new Response("Bad Request", { status: 400 });
    }

    // Proxy to Anthropic with our API key
    const anthropicResponse = await fetch(ANTHROPIC_MESSAGES_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body,
    });

    // Return Anthropic's response verbatim (same status, same body)
    const responseBody = await anthropicResponse.text();
    return new Response(responseBody, {
      status: anthropicResponse.status,
      headers: {
        "Content-Type": "application/json",
      },
    });
  },
};
