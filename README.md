# SuperPaste

**Press Option+V. The right text appears in whatever you're typing into.**

SuperPaste is a small native macOS app that captures only the active window when you hit a hotkey, asks the SuperPaste backend for the best response, and pastes it directly at your cursor. No app switching, no prompting, no preview step.

It is fully open source under the MIT license. The hosted service is a **$5/month subscription** (cancel anytime) that covers Claude usage — up to **100 AI responses per day** — plus the signed/notarized DMG and in-app update checks. New installs get a **7-day free trial**: no card required, limited to 15 responses/day.

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

Download the signed/notarized DMG and drag SuperPaste to Applications — macOS will let you launch it without any "unidentified developer" friction. You start on the 7-day free trial (no card, 15 responses/day); after that it's $5/month via Polar with 100 responses/day, cancel anytime. SuperPaste checks for signed updates automatically; a red dot appears in the menu bar and Settings when one is ready, and you can install it without leaving the app.

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

Nobody ends up posting the same paragraph as everyone else, and the facts, the link, and your guardrails survive every version.

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
| Required facts | no | Up to 8; every post carries all of them |
| Hashtags | no | Up to 6; only used where they read naturally |
| Tone | no | A few words |
| Prohibited claims | no | Up to 10; a draft that uses one is refused, not pasted |
| Supported platforms | yes | Only these are targeted |
| Expiration date | no | After it, the link stops working |

You get a link to send out. To preview it, copy it and press ⌥V in a LinkedIn or X box yourself — that is exactly what a sharer gets, through the same code path.

The `/share` page a recipient lands on doesn't generate anything. It shows the campaign, spells out the three steps, and offers the download if they don't have SuperPaste yet.

### Why generation lives in the app

Campaign generation happens **only** through `POST /v1/messages`, behind the device-id and trial/license gate the paste product already has. Magic Copy costs a user's daily quota exactly like any other paste.

An earlier draft of this feature exposed an anonymous `/v1/smart-share/generate` so a browser could generate. That was an open inference faucet: campaign creation is unauthenticated and `intent` is free text, so anyone could mint a campaign and generate against it without ever holding a license. Rate limits only slow that down. Moving generation into the app closes it, and needs no accounts, no sessions, and no new identity system.

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
- Because Magic Copy pastes with no review screen, guardrails are **enforced** rather than reported: a missing required URL is appended, and a draft that uses a prohibited claim is refused outright rather than typed into someone's composer.
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
- Smart Share Links send the campaign and the chosen platform to the backend to write the post, and nothing else — no visitor identifier, no cookie, no stored record of who opened a link.
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