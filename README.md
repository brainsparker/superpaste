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

Download the signed/notarized DMG and drag SuperPaste to Applications — macOS will let you launch it without any "unidentified developer" friction. You start on the 7-day free trial (no card, 15 responses/day); after that it's $5/month via Polar with 100 responses/day, cancel anytime. The app checks GitHub releases and offers new versions when they're available.

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

## Privacy

- SuperPaste captures one active-window screenshot only when you press Option+V.
- The screenshot is sent to the SuperPaste backend for generation and immediately discarded after processing. In bring-your-own-key mode it goes directly from your Mac to Anthropic — the SuperPaste backend never sees it.
- Accessibility is used for the global hotkey and the final `⌘V` paste.
- No analytics, no telemetry, no crash reporting. If something goes wrong, please file an issue.

Full details: [Privacy policy](https://superpaste.ai/privacy) · [Terms](https://superpaste.ai/terms) · [Refunds](https://superpaste.ai/refunds)

## Architecture

- **Swift / SwiftUI** native macOS app, built with SwiftPM
- **Cloudflare Worker** backend proxy for model requests
- **CGEvent** tap for the hotkey, **NSPasteboard** + synthesized `⌘V` for the paste

## Contributing

PRs welcome. A few ground rules:

- No telemetry, ever.
- Keep the app narrow: active-window context in, generated text pasted in place.
- Do not add extra prompting, preview, or app-switching steps to the primary flow.
- Tests where they actually catch things; not for coverage's sake.

For substantial changes, please open an issue first so we can sort the design out before you write the code.

## License

[MIT](./LICENSE). Use it however you want. Attribution appreciated but not required.
