# SuperPaste

**Press Option+V. The right text appears in whatever you're typing into.**

SuperPaste is a small native macOS app that captures only the active window when you hit a hotkey, asks the SuperPaste backend for the best response, and pastes it directly at your cursor. No app switching, no prompting, no preview step.

It is fully open source under the MIT license. The hosted service is a **$5/month subscription** (cancel anytime) that covers Claude usage — up to **100 AI responses per day** — plus the signed/notarized DMG and in-app update checks. New installs get a **7-day free trial**: no card required, limited to 15 responses/day.

Don't want to subscribe? Enable **Settings → "Use your own Anthropic API key"** and SuperPaste is genuinely free — it works in the paid build and in builds you compile from source, sending screenshots straight from your Mac to Anthropic. No telemetry either way.

---

## How it works

1. You place your cursor in any text field.
2. You press **Option+V**.
3. SuperPaste captures the active window context.
4. The backend writes the appropriate response — a Slack reply, an email, the next line of code, an answer to a question.
5. SuperPaste writes the result to the clipboard and synthesizes a `⌘V` to paste it where your cursor is.

## Requirements

- **macOS 14** or later
- **Swift toolchain** for building from source
- **Internet access** for the SuperPaste backend request

## Install

### From the signed DMG

Download the signed/notarized DMG and drag SuperPaste to Applications — macOS will let you launch it without any "unidentified developer" friction. You start on the 7-day free trial (no card, 15 responses/day); after that it's $5/month via Polar with 100 responses/day, cancel anytime. SuperPaste checks for signed updates automatically; a red dot appears in the menu bar and Settings when one is ready, and you can install it without leaving the app.

→ [Download SuperPaste.dmg](https://github.com/brainsparker/superpaste/releases/latest/download/SuperPaste.dmg)

Even in the paid build, **Settings → "Use your own Anthropic API key"** switches to your own Anthropic account and makes SuperPaste free — no subscription needed.

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

The result lands at `SuperPaste.app` in the repo root. Drag it to `/Applications` if you want it there.

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

To replay the full first-run permission flow:

```bash
./build.sh --fresh-permissions
```

If System Settings shows Screen Recording enabled but the setup window has not advanced, use the in-app **Relaunch SuperPaste** button. macOS sometimes applies Screen Recording grants only to a fresh app process.

The reset command is also available directly:

```bash
./bin/reset-onboarding.sh --permissions
```

## Smart Share Links

**Share the message, not the copy.**

A Smart Share Link lets you define what you want people to get across without writing the post for them. You describe the message, the facts that must survive, the link, and what nobody should claim. Everyone who opens your link picks where they're posting and gets their own version written for that platform.

Nobody ends up posting the same paragraph as everyone else, and the facts, the link, and your guardrails survive every version.

This is separate from the Option+V paste flow — it's a web feature, and the macOS app is not involved.

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
| Prohibited claims | no | Up to 10; drafts are checked against these |
| Supported platforms | yes | Only these are offered to sharers |
| Expiration date | no | After it, the link stops working |

You get a link, plus a LinkedIn and X preview so you can see what people will actually receive.

### Opening a campaign

The link goes to `/share`. The page shows the campaign name, exactly which parts came from the campaign author, and a platform picker: LinkedIn, X, Threads, Bluesky, Facebook, Reddit, Slack, Email, or generic. Pick one and you get a post you can copy, edit, or regenerate for something different. Where a platform has a share URL that genuinely prefills text, there's a button to open it.

**SuperPaste never posts anything for you.** Every draft is reviewed by the person sharing it before it goes anywhere.

### Where the campaign lives

There is no campaign database. The whole campaign is encoded into the link's **fragment** (`/share#c=…`), which means:

- Nothing is stored on a server, and the feature works without a hosted service.
- Fragments aren't sent in the HTTP request line, so campaign contents stay out of server logs and `Referer` headers.
- Anyone holding the link can decode it. **Never put anything private in a campaign.**
- A published link can't be edited or revoked. To change a campaign, make a new link.

Storage sits behind `SmartShareCampaignProvider` (`server/src/smartshare/provider.ts`), so a hosted provider with short opaque ids can be added later without touching the schema, prompts, or UI.

### Layout

Everything lives in the Worker plus two static pages. The macOS app is untouched.

```
server/src/smartshare/
  schema.ts      types, validation, field limits, URL + expiry checks
  codec.ts       campaign <-> link token, fragment-based link building
  platforms.ts   per-platform voice, length, and share-URL config
  prompt.ts      prompt construction and post-generation guardrail checks
  generate.ts    the only place that calls a model
  provider.ts    storage interface + the local encoded-link provider
  analytics.ts   interface + no-op only (see below)
  routes.ts      HTTP surface, CORS, rate limits, daily cost ceiling
website/
  smart-share.html   campaign creation + LinkedIn/X preview
  share.html         the page a sharer opens
```

Platform rules live only in `platforms.ts`; the UI reads them over HTTP from `GET /v1/smart-share/platforms` so nothing is duplicated in page code. Adding a platform means one entry there plus one union member in `schema.ts`.

### Treating campaign links as hostile

A campaign arrives from a URL a stranger can hand-edit, so:

- Every field is schema-validated with a hard length cap; control characters and bidi overrides are stripped.
- URLs must be `http`/`https` with no embedded credentials — `javascript:` and `data:` are rejected at the schema boundary, not at render time.
- Oversized payloads are rejected before being parsed, and unknown/newer schema versions are refused rather than half-understood.
- **Campaign text never enters the system prompt.** It goes in the user message, JSON-encoded, inside a block whose delimiter carries a nonce the campaign author cannot predict. There's a test asserting no campaign text reaches the system prompt on any platform.
- The share page renders every campaign-supplied value through `textContent`, never `innerHTML`, and labels which content came from the campaign.
- Generated copy is checked for the required link, prohibited phrases, and platform length limits; anything that fails is shown to the user as a warning rather than quietly returned.

`/v1/smart-share/generate` is necessarily unauthenticated, so it carries a per-IP burst limiter, a global daily ceiling with **its own** KV counter (Smart Share traffic can never eat the paste product's trial or licensed capacity), and hard request-size caps.

### Analytics

There are none, and there won't be. `analytics.ts` defines an interface and a no-op, because the contributing rule is "No telemetry, ever." The seam exists only so someone self-hosting can measure their own campaigns; the shipped build keeps the no-op.

### Working on it

```bash
cd server
npm install
npm test        # node:test, no test framework dependency
npm run typecheck
```

Tests cover schema validation, link parsing, prompt construction, and the full create → resolve → generate route path with a stubbed model. `npm test` runs the TypeScript sources directly — Node 22 strips types natively, so there's no build step and no test runner to install.

## Privacy

- SuperPaste captures one active-window screenshot only when you press Option+V.
- The screenshot is sent to the SuperPaste backend for generation and immediately discarded after processing. In bring-your-own-key mode it goes directly from your Mac to Anthropic — the SuperPaste backend never sees it.
- Accessibility is used for the global hotkey and the final `⌘V` paste.
- Smart Share Links send the campaign and the chosen platform to the backend to write the post, and nothing else — no visitor identifier, no cookie, no stored record of who opened a link.
- No analytics, no telemetry, no crash reporting. If something goes wrong, please file an issue.

Full details: [Privacy policy](https://superpaste.ai/privacy) · [Terms](https://superpaste.ai/terms) · [Refunds](https://superpaste.ai/refunds)

## Architecture

- **Swift / SwiftUI** native macOS app, built with SwiftPM
- **Cloudflare Worker** backend proxy for model requests
- **CGEvent** tap for the hotkey, **NSPasteboard** + synthesized `⌘V` for the paste
- **Sparkle 2** for signed, automatic in-app updates
- **Smart Share Links** as a self-contained Worker module plus two static pages, with no coupling to the paste path

## Contributing

PRs welcome. A few ground rules:

- No telemetry, ever.
- Keep the app narrow: active-window context in, generated text pasted in place.
- Do not add extra prompting, preview, or app-switching steps to the primary flow.
- Tests where they actually catch things; not for coverage's sake.

For substantial changes, please open an issue first so we can sort the design out before you write the code.

## License

[MIT](./LICENSE). Use it however you want. Attribution appreciated but not required.
