# SuperPaste

**Press Option+V. The right text appears in whatever you're typing into.**

SuperPaste is a small native macOS app that captures only the active window when you hit a hotkey, asks the SuperPaste backend for the best response, and pastes it directly at your cursor. No app switching, no prompting, no preview step.

It is fully open source under the MIT license. The hosted service is a **$5/month subscription** (cancel anytime) that covers Claude usage — up to **100 AI responses per day** — plus the signed/notarized DMG and in-app update checks. Trials require signing in with a **verified email account** and last **7 days** from the account's first request: no card required, with **15 responses/day per account** across devices and networks.

**Don't want to subscribe? Bring your own API key** — Anthropic, OpenAI, or OpenRouter — and SuperPaste is genuinely free. It works in the paid build and in builds you compile from source, sending screenshots straight from your Mac to your chosen provider. No telemetry either way.

Want nothing to leave your Mac? Pick **Ollama (local)** or **LM Studio (local)** in Settings. No API key, no account: SuperPaste finds the server on its default port, lists the models you have installed, and runs the screenshot through one of them on-device. Any other **OpenAI-compatible endpoint** (vLLM, llama.cpp, a gateway) works through the Custom provider, with the API key optional. See [Run fully local](#run-fully-local-ollama-or-lm-studio).

---

## How it works

1. You place your cursor in any text field.
2. You press **Option+V**.
3. SuperPaste captures the active window context.
4. Your chosen AI provider generates the appropriate response — a Slack reply, an email, the next line of code, an answer to a question.
5. SuperPaste writes the result to the clipboard and synthesizes a `⌘V` to paste it where your cursor is.

## Requirements

- **macOS 14** or later
- **Swift toolchain** for building from source
- **Internet access** for the AI provider request (except local models)

## Install

### From the signed DMG

Download the signed/notarized DMG and drag SuperPaste to Applications — macOS will let you launch it without any "unidentified developer" friction. Sign in with a verified email account for the 7-day free trial (no card, 15 responses/day per account); after that it's $5/month via Polar with 100 responses/day, cancel anytime. SuperPaste checks for signed updates automatically; a red dot appears in the menu bar and Settings when one is ready, and you can install it without leaving the app.

→ [Download SuperPaste.dmg](https://github.com/brainsparker/superpaste/releases/latest/download/SuperPaste.dmg)

Even in the paid build, **Settings → AI Provider** lets you switch to your own API key (Anthropic, OpenAI, OpenRouter, or custom) and SuperPaste stays free — no subscription needed.

### From source (free)

```bash
git clone https://github.com/brainsparker/superpaste
cd superpaste

# One-time toolchain check
./bin/check-toolchain.sh

# One-time local signing identity so macOS permissions survive rebuilds
./setup_codesign.sh

# Build the app
./build.sh
```

The result lands at `SuperPaste Dev.app` in the repo root. It has a separate bundle identity and preferences from the signed release, so development builds cannot replace the release's macOS permission grants. Grant permissions to **SuperPaste Dev** once. Development builds require the stable certificate from `./setup_codesign.sh` and do not install release updates.

Use the signed **SuperPaste** release for everyday use. Quit one before using the other: both register the same default hotkey. If you have an older local `SuperPaste.app` in the repo root, stop using that copy; it shares the release's bundle ID but has a different signing identity.

The first time you launch SuperPaste it will:
1. Ask for Screen Recording permission so it can capture the active window on demand
2. Ask for Accessibility permission so it can register Option+V and paste the response in place

After that, hit Option+V anywhere.

### Development permission testing

macOS ties Screen Recording and Accessibility grants to the app bundle id and signing identity. Run `./setup_codesign.sh` once before testing; otherwise Accessibility can be lost on every rebuild.

To inspect the local permission test setup without resetting anything:

```bash
./bin/permissions-doctor.sh
```

To check whether the built SuperPaste app can use its current permissions:

```bash
./bin/permissions-probe.sh
```

The probe exits `0` when Screen Recording, Accessibility, and the hotkey event tap are usable for the signed app. It exits `1` while a permission is still missing.

To replay onboarding without touching macOS permission grants:

```bash
./build.sh --fresh
```

The build, reset, doctor, and probe scripts target **SuperPaste Dev** by default, leaving the release's preferences and permissions alone. `--fresh-permissions` deliberately resets only the development app's macOS grants. To check development bundle isolation after building, run `./scripts/test-dev-bundle.sh`.

To replay the full first-run permission flow:

```bash
./build.sh --fresh-permissions
```

If System Settings shows Screen Recording enabled but the setup window has not advanced, use the in-app **Relaunch SuperPaste** button. macOS sometimes applies Screen Recording grants only to a fresh app process.

The reset command is also available directly:

```bash
./bin/reset-onboarding.sh --permissions
```

## Run fully local (Ollama or LM Studio)

SuperPaste can run entirely on your Mac. The screenshot goes to a model server on `localhost` and never touches the network.

1. Install [Ollama](https://ollama.com/download) or [LM Studio](https://lmstudio.ai) and pull a vision-capable model. Vision matters: SuperPaste sends a screenshot, not text.
   ```bash
   ollama pull qwen3-vl        # or: gemma4, llama3.2-vision
   ```
   In LM Studio, download a vision model (Qwen3-VL, Gemma 4) and start the local server from the Developer tab.
2. In SuperPaste, open **Settings → AI Provider** and choose **Ollama (local)** or **LM Studio (local)**.
3. SuperPaste checks the server (`localhost:11434` for Ollama, `localhost:1234` for LM Studio), shows "Connected" with the installed models, and marks the ones that can read screenshots. Leave the model on **Auto** to use the first vision model it finds, or pick one.

That's the whole setup. No API key field to fill, no trial clock, no subscription. Everything the app knows about the server (host and port, chosen model) is visible in **Settings → Diagnostics**.

Notes:

- Moved the server to another port or machine? Enter it in the **Server address** field. Any of `localhost:11434`, `http://host:port/v1`, or a full `/v1/chat/completions` URL is accepted. SuperPaste tells you whether the address is on this Mac or over the network.
- Turned on authentication in LM Studio, or put a gateway in front of Ollama? Expand **API key (optional)** and save the key; it stays in the macOS Keychain.
- Other OpenAI-compatible servers (vLLM, llama.cpp `llama-server`, Jan, MLX servers) work through **Custom (OpenAI-compatible)**. The key is optional there too, and the same model list and connection check apply when the server exposes `/v1/models`.
- A text-only model will answer, but it cannot see the screenshot. SuperPaste warns when the selected model doesn't look vision-capable.
- Local models are smaller than the hosted Claude model, so expect plainer replies, and give the first request a few extra seconds while the model loads.

## Smart Share Links

**Share the message, not the copy.**

A Smart Share Link lets you define what you want people to get across without writing the post for them. You describe the message, the facts that must survive, the link, and what nobody should claim. Everyone who shares it gets their own version, written for wherever they're posting.

Drafts can vary. Supplied fact text and the required URL are preserved deterministically; blocked phrases use normalized matching. This is not a semantic fact-checker: review claims before posting.

### Magic Copy — how sharing actually works

There is no web app to sign into and no platform picker. Sharing a campaign is the same hotkey you already use:

1. **Copy the campaign link.** That's the whole setup — the campaign travels inside the link.
2. **Click into the box you'd post in** — LinkedIn, X, Threads, Bluesky, Facebook, Reddit, Slack, an email.
3. **Press ⌥V.** SuperPaste notices the campaign link on your clipboard, works out which platform you're in from the frontmost app and window title, writes a post for it, and types it in place.

Press ⌥V again somewhere else and you get a different post, tuned to that platform. The clipboard is handed back afterwards, so the campaign link is still there for the next one.

Magic Copy takes **no screenshot**. The campaign supplies the content and the frontmost app supplies the destination, so there is nothing to read off your screen — which also makes it faster than a normal paste.

An ordinary URL on the clipboard changes nothing. Detection matches only SuperPaste's own `/share#c=…` links, so the primary flow behaves exactly as before.

### Creating a campaign

Go to [superpaste.ai/smart-share](https://superpaste.ai/smart-share) and fill in:

| Field | Required | Notes |
|---|---|---|
| Campaign name | yes | Shown to people who open the link |
| Message / intent | yes | The point to get across, not the wording |
| Link | no | http/https only, included verbatim with no tracking added |
| Required facts | no | Up to 8; missing supplied fact text is appended verbatim |
| Hashtags | no | Up to 6; only used where they read naturally |
| Tone | no | A few words |
| Blocked phrases | no | Up to 10; normalized phrase matches are refused after all repairs; this does not detect semantic paraphrases |
| Supported platforms | yes | Only these are targeted |
| Expiration date | no | After it, the link stops working |

You get a link to send out. To preview it, copy it and press ⌥V in a LinkedIn or X box yourself — that is exactly what a sharer gets, through the same code path.

The `/share` page a recipient lands on doesn't generate anything. It shows the campaign, spells out the three steps, and offers the download if they don't have SuperPaste yet.

### Why generation lives in the app

Campaign generation happens **only** through `POST /v1/messages`, behind the verified-account or license gate the paste product already has. Magic Copy costs a user's daily quota exactly like any other paste.

An earlier draft of this feature exposed an anonymous `/v1/smart-share/generate` so a browser could generate. That was an open inference faucet: campaign creation is unauthenticated and `intent` is free text, so anyone could mint a campaign and generate against it without ever holding a license. Rate limits only slow that down. Generation uses the same entitlement checks as a normal paste: a verified trial account or a validated paid license. Public campaign creation and link resolution never grant access to model generation.

The three remaining `/v1/smart-share/*` routes — `platforms`, `campaigns`, `resolve` — never call a model. They validate a draft, encode a link, and decode one for display.

**Known gap:** Magic Copy needs the SuperPaste backend, so it does not work in bring-your-own-key mode, where the app talks to Anthropic directly and never reaches the Worker. Pressing ⌥V on a campaign link in that mode says so rather than pasting something unrelated. Supporting it cleanly means a route that returns the built prompt (no model call, so no cost) which the app then sends to Anthropic itself — that keeps one definition of the prompt instead of a second copy in Swift.

### Where the campaign lives

There is no campaign database. The whole campaign is encoded into the link's **fragment** (`/share#c=…`), which means:

- Nothing is stored on a server, and the feature works without a hosted service.
- Fragments aren't sent in the HTTP request line, so campaign contents stay out of server logs and `Referer` headers.
- Anyone holding the link can decode it. **Never put anything private in a campaign.**
- A published link can't be edited or revoked. To change a campaign, make a new link.

Storage sits behind `SmartShareCampaignProvider` (`server/src/smartshare/provider.ts`), so a hosted provider with short opaque ids can be added later without touching the schema, prompts, or UI.

### Layout

```
server/src/smartshare/
  schema.ts      types, validation, field limits, URL + expiry checks
  codec.ts       campaign <-> link token, fragment-based link building
  platforms.ts   per-platform voice, length, and share-URL config
  detect.ts      frontmost app + window title -> destination platform
  prompt.ts      prompt construction and guardrail enforcement
  provider.ts    storage interface + the local encoded-link provider
  analytics.ts   interface + no-op only (see below)
  routes.ts      the three non-generating HTTP routes
server/src/index.ts          Magic Copy rides /v1/messages
SuperPaste/Sources/
  Utilities/SmartShareLink.swift   spots a campaign link on the clipboard
  Services/LLMService.swift        processShareCampaign
  Models/AppState.swift            the Magic Copy branch of the pipeline
website/
  smart-share.html   campaign creation
  share.html         what a recipient lands on
```

Platform voice, length limits, and platform **detection** all live server-side. Window titles change whenever a social network reskins, so a detection fix ships without an app release — the same reason the paste prompt lives in the Worker. Adding a platform means one entry in `platforms.ts` plus one union member in `schema.ts`.

### Treating campaign links as hostile

A campaign arrives from a URL a stranger can hand-edit, so:

- Every field is schema-validated with a hard length cap; control characters and bidi overrides are stripped.
- URLs must be `http`/`https` with no embedded credentials — `javascript:` and `data:` are rejected at the schema boundary, not at render time.
- Oversized payloads are rejected before being parsed, and unknown/newer schema versions are refused rather than half-understood.
- An invalid or expired link is refused **before** the quota gate, so a dead link costs nothing.
- **Campaign text never enters the system prompt.** It goes in the user message, JSON-encoded, inside a block whose delimiter carries a nonce the campaign author cannot predict. There are tests asserting no campaign text reaches the system prompt on any platform.
- Because Magic Copy pastes with no review screen, guardrails are **enforced** rather than reported: a missing required URL is appended, and a draft containing a normalized blocked phrase is refused after all repairs rather than typed into someone's composer.
- Upstream errors on the share path are never forwarded, since an error body could echo a third party's campaign text back to the sharer.
- The `/share` page renders campaign values through `textContent`, never `innerHTML`, and labels which content came from the campaign.
- Nothing is ever auto-posted. The text lands in the composer and stops there.

### Analytics

There are none, and there won't be. `analytics.ts` defines an interface and a no-op, because the contributing rule is "No telemetry, ever." The seam exists only so someone self-hosting can measure their own campaigns; the shipped build keeps the no-op.

### Working on it

```bash
cd server
npm install
npm test        # vitest
npm run typecheck
```

Tests cover schema validation, link parsing, prompt construction, platform config, platform detection, and the full Magic Copy path through `/v1/messages` with a stubbed model — including that it consumes the same quota and is refused by the same trial and rate limits as a normal paste.

## Privacy

- SuperPaste captures one active-window screenshot only when you press Option+V.
- The screenshot is sent to your chosen AI provider for generation and immediately discarded after processing. With the hosted plan it goes through the SuperPaste backend; with a bring-your-own-key it goes directly from your Mac to the provider — the SuperPaste backend never sees it. With a local provider (Ollama, LM Studio) it never leaves your Mac at all.
- Accessibility is used for the global hotkey and the final `⌘V` paste.
- Smart Share Links send the campaign and the chosen platform to the backend to write the post, and no screenshot. Link resolution has no visitor tracking; hosted generation uses the same entitlement and quota controls as other requests.
- No analytics, no telemetry, no crash reporting. If something goes wrong, please file an issue.

Full details: [Privacy policy](https://superpaste.ai/privacy) · [Terms](https://superpaste.ai/terms) · [Refunds](https://superpaste.ai/refunds)

## Architecture

- **Swift / SwiftUI** native macOS app, built with SwiftPM
- **Cloudflare Worker** backend proxy for model requests (hosted plan only)
- **CGEvent** tap for the hotkey, **NSPasteboard** + synthesized `⌘V` for the paste
- **Sparkle 2** for signed, automatic in-app updates
- **Provider-agnostic LLM layer** — OpenAI-compatible, Anthropic, and custom endpoints
- **Smart Share Links / Magic Copy** — a Worker module plus two static pages; campaign generation rides the existing `/v1/messages` route so it reuses the trial and license gate

## Contributing

PRs welcome. A few ground rules:

- No telemetry, ever.
- Keep the app narrow: active-window context in, generated text pasted in place.
- Do not add extra prompting, preview, or app-switching steps to the primary flow.
- Tests where they actually catch things; not for coverage's sake.

For substantial changes, please open an issue first so we can sort the design out before you write the code.

## License

[MIT](./LICENSE). Use it however you want. Attribution appreciated but not required.

## Hosted request and quota hardening

All generation requires the `QUOTA_LEDGER` SQLite-backed Durable Object binding and migration in `server/wrangler.toml`. Reservations atomically count a generation against its principal and tier-wide daily allowance **before** inference. Dispatched attempts remain charged on upstream errors/timeouts because a transport failure does not prove that no inference occurred. There is no automatic retry in this branch; coordinate the separate retry PR with this reservation boundary. A deliberate new hotkey request consumes a new reservation.

Hosted trials require an OpenID Connect provider configured as a **native/public client**, with authorization code + PKCE (S256), no client secret, signed RS256 or ES256 ID tokens, and a real verified-email claim. Configure `TRIAL_OIDC_ISSUER` (the exact HTTPS discovery issuer, including its trailing slash if present) and `TRIAL_OIDC_CLIENT_ID` as Worker variables before deploying. Register these exact callback URIs with the provider:

- Release: `com.superpaste.app:/oauth/callback`
- Development: `com.superpaste.app.dev:/oauth/callback`

Enable `openid email` scopes and require email verification at the provider. The ID token must include `sub`, `iat`, `exp`, `email`, and boolean `email_verified: true`, with this native client as its audience. Discovery must publish HTTPS authorization, token, and JWKS endpoints. If the provider advertises `offline_access`, enable rotating refresh tokens for the native client; otherwise users sign in again when their ID token expires. Never add a client secret to the app. Use a dedicated client for SuperPaste, keep issuer/client IDs stable, and preserve subjects when migrating providers: changing an account's issuer or subject creates a new trial identity.

The app fetches public configuration from `GET /v1/trial-auth/config`, opens the system authentication browser only on an explicit sign-in action, checks the callback state, exchanges the code with PKCE, and submits the ID token and nonce to `POST /v1/trial-auth/verify`. Credentials are saved in Keychain only after the Worker verifies the signature, issuer, audience, authorized party, expiry, nonce, and verified-email claim. Refresh happens before capture and never opens a browser from the hotkey. Trial status checks do not start the trial or spend quota. Paid licenses and direct/local providers do not require trial sign-in.

Quota identity is a SHA-256 hash of the verified issuer and subject. Changing email, device ID, or public IP does not replenish that account's allowance; separate verified accounts on one network have separate trials. Public IP is used only for burst limits. Raw subjects, emails, and IPs are not written to quota storage. Trial first-use records persist to prevent resets; dated usage records enforce access/cost limits. Licensed quotas use the hash of the validated license, shared across devices. Missing storage or identity-provider configuration fails closed; there is no anonymous fallback. Verified accounts reduce abuse but do not guarantee one account per person. Provider-side signup protections should be enabled.

Deploy the app and Worker as a coordinated update: older clients without account sign-in will receive a sign-in-required response for hosted trials. Existing device/network trial records cannot establish a verified account; its seven-day clock starts at its first account reservation.

This repository does not provision an identity-provider tenant. Configure the issuer, public client, callback allowlist, verified-email policy, and refresh-token policy before deployment, then smoke-test a verified and an unverified account through the real browser. Unit and Worker-runtime tests use locally signed account fixtures and make no calls to a live identity provider.

The 35-second Worker budget includes input parsing and license checks, and ends before the app's 45-second timeout. Positive license validations remain cached for up to one hour. Dependency failures cannot validate unknown keys. Image checks validate encoding, type headers, and pixel dimensions; the provider still validates compressed pixel data.

Cloudflare documents [transactional storage](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/) and the [SQLite class migration format](https://developers.cloudflare.com/durable-objects/reference/durable-object-class-migrations-legacy/) used here.

Endpoint settings now require **Connect** to commit an edited server address. Custom/local server keys are bound to that endpoint scope. Existing unscoped custom/local keys must be entered again for their intended server; fixed Anthropic/OpenAI/OpenRouter keys are unaffected. Redirects are refused for provider requests so screenshots and credentials do not follow them.

## Release checks

Public releases require a clean intended commit, a new marketing version, a strictly newer numeric build version, a Developer ID identity, and the `superpaste-notary` profile. `scripts/release.sh --preflight-only` validates prerequisites without building or publishing. `--skip-notarize` is allowed only with `--local`. Published assets are immutable.

Release packaging builds both arm64 and x86_64, verifies all packaged Mach-O slices before signing, records the source commit in the bundle, and requires accepted notarization and staple validation before publishing. Local packaging remains available with `scripts/release.sh --local`. Run `python3 -m unittest discover -s scripts/tests -v` for the release-policy regression tests. Run `cd server && npm run test:quota-runtime` to exercise real SQLite reservations, last-slot concurrency, and persistence across a local runtime restart; it also verifies locally signed trial tokens through the real Worker with a stubbed identity provider and model. It never contacts a live model or deploys a Worker.
