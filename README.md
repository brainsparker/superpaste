# SuperPaste

**See your screen. Get the right response. Paste instantly.**

SuperPaste is a macOS app for people who write all day (email, Slack, docs, support, sales, recruiting).

Press **⌥S** while looking at any conversation or draft, and SuperPaste generates a context-aware response you can paste with **⌘V**.

---

## Why SuperPaste

Most AI writing tools make you copy text into a chat box, explain context, then copy back.

SuperPaste removes that workflow tax:

- **No context switching** — stay in your current app
- **No manual prompt crafting** — SuperPaste reads visible context
- **Faster response loops** — hotkey in, hotkey out

If your day is full of "quick replies" that still take too long, SuperPaste is built for you.

---

## Who it’s for (ICP)

- Founders and operators handling high message volume
- Sales and customer success teams replying in real time
- Recruiters and hiring managers drafting outreach
- Anyone who writes repetitive responses across apps

---

## How it works

1. Open any app (Gmail, Slack, Notion, Linear, docs, etc.)
2. Look at the message/thread/content you want to respond to
3. Press **⌥S**
4. SuperPaste captures your active window and generates a response
5. Press **⌘V** to paste

---

## Key benefits

- **Context-aware output** from what’s on your screen
- **System-wide hotkey** works across apps
- **Minimal UI** with a lightweight HUD
- **Bring your own Anthropic API key**
- **Privacy-first behavior** (no continuous recording)

---

## Privacy and permissions

SuperPaste requires **Screen Recording** permission on macOS so it can capture a screenshot *only when you trigger the hotkey*.

What SuperPaste sends:
- Screenshot of your active window
- App name and window title

What SuperPaste does **not** do:
- Continuous recording
- Persistent screenshot storage
- File-system scraping

---

## Setup

### Requirements

- macOS
- Xcode 15+
- Anthropic API key

### Run locally

```bash
git clone git@github.com:brainsparker/superpaste.git
cd superpaste/SuperPaste
open Package.swift
```

Then run from Xcode, grant Screen Recording permission, add your Anthropic key in Settings, and use **⌥S**.

---

## Product positioning in one line

**SuperPaste is the fastest way to generate high-quality replies from on-screen context without leaving your workflow.**

---

## Feedback

- Issues: https://github.com/brainsparker/superpaste/issues
- Feedback: feedback@superpaste.app

If this project saves you time, star the repo and share it with another heavy writer.
