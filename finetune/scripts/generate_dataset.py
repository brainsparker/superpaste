#!/usr/bin/env python3
"""
Distillation dataset generator for the SuperPaste local SLM. (v2)

Pipeline:
  Stage 1 (scenario synthesis): Claude writes a realistic <context> block
          for a sampled (category, surface, persona) combination, with
          CLEAN screen text grounded in an app-specific chrome template.
  Stage 2 (OCR noise, in Python): mechanical noise is injected into
          screen_text: character confusions, dropped spaces, merged lines.
          Deterministic-ish and far more realistic than asking a model
          to "write noisy OCR".
  Stage 3 (teacher labeling): Claude produces the ideal paste string for
          the NOISED context, using the same system prompt the SLM will
          be trained on. The teacher sees exactly what the student will.

Output: train.jsonl / valid.jsonl / test.jsonl in MLX-LM chat format.

Usage:
  export ANTHROPIC_API_KEY=sk-ant-...
  python3 generate_dataset.py --n 200 --out ../data   # inspect first
  python3 generate_dataset.py --n 2000 --out ../data
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import anthropic

TEACHER_MODEL = os.environ.get("TEACHER_MODEL", "claude-sonnet-4-5")

SYSTEM_PROMPT = (
    "You are SuperPaste, running locally on the user's Mac. You are given the "
    "context of the active window. Write exactly the text that should be pasted "
    "at the user's cursor. Match the register of the surrounding content: a "
    "Slack reply is casual, an email is complete, code continues the file's "
    "style. If field_content shows a partial draft, continue it from the cursor "
    "without repeating any of it, joining cleanly. Output only the paste text. "
    "Never explain, never wrap in quotes."
)

# ---------------------------------------------------------------------------
# Surface library: what Vision OCR actually captures per app.
# `chrome` describes the UI junk that bleeds into screen_text; the scenario
# writer is told to include a realistic subset of it.
# ---------------------------------------------------------------------------

SURFACES = {
    "slack": dict(
        app="Slack",
        window="#<channel> | <Workspace name> - Slack, or a DM: <Person> - <Workspace> - Slack",
        field="message input",
        chrome="Left sidebar channel names (# prefixed) and DM names may appear as a column of short lines at the top of screen_text. Messages carry 'Name  H:MM AM/PM' headers. Threads show 'N replies' / 'Reply in thread…'. Reactions appear as ':emoji_name: N'. 'Huddle', 'Later', 'Add bookmark' toolbar words can appear.",
    ),
    "imessage": dict(
        app="Messages",
        window="<Contact name or group name>",
        field="message input",
        chrome="Short bubbles without timestamps on every line; occasional 'Today H:MM PM' divider; 'Delivered' or 'Read H:MM PM' under the last outgoing message; 'iMessage' placeholder.",
    ),
    "discord": dict(
        app="Discord",
        window="#<channel> | <Server>",
        field="message input",
        chrome="Server/channel sidebar words, usernames with discriminators or display names, 'Today at H:MM PM' timestamps, 'NEW' unread divider, emoji shortcodes.",
    ),
    "gmail": dict(
        app="Google Chrome",
        window="<subject or Inbox (N)> - <user email> - Gmail",
        field="email body (reply box or compose window)",
        chrome="Toolbar words (Send, Formatting options, Attach files), quoted thread below with 'On <date>, <Name> <email> wrote:' lines, signature fragments, 'Reply' 'Reply all' 'Forward' labels. Inbox rows may bleed in from behind a compose overlay.",
    ),
    "apple_mail": dict(
        app="Mail",
        window="Re: <subject> or <subject>",
        field="email body",
        chrome="To:/Cc:/Subject: header lines, 'Sent from my iPhone' in quoted text, previous messages with 'On <date>, at <time>, <name> wrote:' markers.",
    ),
    "vscode": dict(
        app="Code",
        window="<filename> — <project folder>",
        field="code editor",
        chrome="File tab names, breadcrumb path segments, line numbers may prefix some lines (OCR merges them with code), status bar fragments (Ln 42, Col 7, UTF-8, LF, language name), minimap is not captured as text but explorer filenames may be.",
    ),
    "iterm": dict(
        app="iTerm2",
        window="<user>@<host>: <cwd>",
        field="terminal prompt",
        chrome="Shell prompts (user@host dir %), previous command outputs including error messages, exit codes, paths. The right paste is usually a shell command.",
    ),
    "notion": dict(
        app="Notion",
        window="<Page title>",
        field="page body / text block",
        chrome="Sidebar page names, breadcrumbs, 'Add icon' 'Add cover' 'Share' toolbar words, checkbox and bullet glyphs OCR'd as odd characters.",
    ),
    "gdocs": dict(
        app="Google Chrome",
        window="<Doc title> - Google Docs",
        field="document body",
        chrome="Menu bar words (File Edit View Insert Format Tools), toolbar fragments, comment sidebar snippets with names and 'Resolve', page break artifacts.",
    ),
    "linear": dict(
        app="Linear",
        window="<Issue ID> <Issue title>",
        field="comment box",
        chrome="Issue metadata labels (Status, Priority, Assignee, Labels), activity log lines ('<name> changed status from ... to ...'), 'Leave a comment…' placeholder.",
    ),
    "x_twitter": dict(
        app="Google Chrome",
        window="<Name> on X: '<post excerpt>' / X",
        field="reply box",
        chrome="Engagement counts (numbers with K/M suffixes), 'Reply' 'Repost' 'Like' 'Views' words, @handles, 'Post your reply' placeholder, promoted-post fragments.",
    ),
    "browser_form": dict(
        app="Safari",
        window="<Page title>",
        field="form field (varies: search box, application form, support form, checkout field)",
        chrome="Nav bar links, cookie banner fragments, form labels above/beside fields, asterisks on required fields, footer links.",
    ),
    "support_desk": dict(
        app="Google Chrome",
        window="Ticket #<n>: <subject> - <Helpdesk name>",
        field="reply to customer",
        chrome="Ticket metadata (Priority, SLA, Assignee), customer message thread with timestamps, macro/canned-response menu words, 'Internal note' vs 'Public reply' tab labels.",
    ),
}

# Category -> (weight, surface pool, scenario directive)
CATEGORIES = {
    "continue_draft": (20, ["slack", "gmail", "apple_mail", "notion", "gdocs", "imessage", "linear", "support_desk"],
        "field_content contains a HALF-TYPED draft (a sentence or two, cut off mid-thought, no trailing ellipsis). The screen provides the context the draft is responding to. The right paste CONTINUES the draft from the cursor: it must not repeat any of the draft, and must join cleanly with correct leading whitespace and case."),
    "chat_reply": (20, ["slack", "imessage", "discord"],
        "field_content is (empty). The conversation implies the user needs to reply. The most recent message is the one to respond to; earlier messages set context."),
    "email_reply": (10, ["gmail", "apple_mail"],
        "field_content is (empty). A quoted email thread is on screen; the user is replying. The paste is a complete reply body (greeting optional and situational, no subject line)."),
    "email_compose": (5, ["gmail", "apple_mail"],
        "field_content is (empty). A fresh compose window; the To/Subject lines reveal intent (e.g. following up after a meeting, sending a deliverable). The paste is a complete short email body."),
    "code": (7, ["vscode"],
        "The visible code has an obvious next step: an unfinished function, a failing pattern to fix, a TODO comment at the cursor. The paste is code in the file's exact style and indentation. No markdown fences."),
    "terminal_command": (5, ["iterm"],
        "Previous commands and their output (often an error) are visible. The paste is the single most sensible next shell command. No leading $ or prompt."),
    "answer_question": (12, ["gdocs", "notion", "browser_form", "support_desk", "slack"],
        "The screen poses a concrete question (a doc comment, a form question, a customer question, a direct question in chat). The cursor is in an answer field. If multiple questions are visible, the paste answers the most recent or the one adjacent to the focused field."),
    "form_field": (8, ["browser_form", "linear", "notion"],
        "A short field: search query, title, event name, one-line form answer. The paste is short and precise, often under 10 words."),
    "rewrite_selection": (8, ["gmail", "gdocs", "notion", "slack"],
        "selected_text contains a rough sentence or paragraph (typos, rambling, wrong tone). The surrounding screen implies the desired fix (e.g. a formal email around a too-casual selection). The paste is the improved replacement for the selection only."),
    "social_reply": (5, ["x_twitter"],
        "A post and some replies are visible; the user is writing a reply. The paste matches the platform register: short, no hashtag spam, no engagement-bait."),
    "low_context": (5, ["browser_form", "imessage", "slack"],
        "Sparse or ambiguous screen content: a mostly empty window, an unclear thread, OCR that caught very little. The right paste is minimal and safe: short, conservative, nothing invented. This teaches the model NOT to hallucinate when context is thin."),
}

# ---------------------------------------------------------------------------
# Diversity sampling done in Python, injected into the prompt.
# ---------------------------------------------------------------------------

DOMAINS = [
    "hospital nursing schedule coordination", "indie game development", "commercial real estate leasing",
    "high school teaching", "restaurant supply ordering", "wedding photography business",
    "biotech lab operations", "freight logistics dispatch", "church volunteer coordination",
    "car dealership sales", "PhD dissertation research", "plumbing contractor quotes",
    "podcast production", "nonprofit grant writing", "e-commerce returns handling",
    "fantasy football league", "apartment hunting", "open source library maintenance",
    "payroll and HR questions", "landscaping crew scheduling", "law firm client intake",
    "food truck permits", "youth soccer team logistics", "insurance claims follow-up",
    "SaaS enterprise sales", "college admissions counseling", "veterinary clinic operations",
    "band tour booking", "home renovation planning", "customs paperwork for imports",
]

NAME_STYLES = [
    "common US names", "Nigerian names", "Indian names", "Vietnamese names",
    "Brazilian names", "Polish names", "Korean names", "Mexican names",
    "Arabic names", "mixed international names", "Filipino names", "Turkish names",
]

FORMALITY = ["very casual (lowercase, abbreviations)", "casual", "neutral professional",
             "formal", "stiff corporate"]

THREAD_DEPTH = ["a single message", "2-3 messages", "a long back-and-forth (6+ messages)"]

RESPONSE_LENGTH = [
    ("one-liner", "the situation calls for a very short paste: one line or even 2-4 words"),
    ("short", "the situation calls for a short paste: 1-3 sentences"),
    ("medium", "the situation calls for a medium paste: a solid paragraph"),
    ("long", "the situation calls for a longer paste: multiple paragraphs (email, doc section, or a code block)"),
]

LANGS = [("English", 0.85), ("Spanish", 0.04), ("German", 0.03), ("French", 0.03),
         ("Portuguese", 0.03), ("Japanese", 0.02)]

# Categories whose correct paste is inherently short: never roll medium/long
# length hints for them (a "long" hint on low_context contradicts the
# directive and produces mushy training data).
SHORT_ONLY_CATEGORIES = {"low_context", "form_field", "terminal_command", "social_reply"}

# Code/terminal surfaces: prose register doesn't apply (no "stiff corporate" bash).
NO_REGISTER_CATEGORIES = {"code", "terminal_command"}

SCENARIO_PROMPT = """You are generating synthetic training data for a Mac utility that pastes AI text at the cursor. Write ONE realistic context block describing the active window of a Mac user, in EXACTLY this format (all seven fields, same order):

<context>
app: <app name>
window: <window title>
focused_field: <role/label of focused text field>
field_placeholder: <placeholder text, or empty>
field_content: <text already typed in the field, or (empty)>
selected_text: <selected text, or (none)>
screen_text:
<visible text as OCR would read it, multiple lines, top-to-bottom>
[cursor is in the <field>]
</context>

Surface: {app}. Window title format: {window}. Focused field: {field}.
What OCR captures on this surface, include a realistic subset: {chrome}

Scenario: {directive}

Grounding for THIS example (follow all of these):
- Subject matter: {domain}. Real, specific details of that world (names of things, quantities, dates), not generic business-speak.
- People: use {names}. {depth_line}
- Register of the on-screen writing: {formality}.
- {length_hint}.
- Language of screen content: {lang}.{lang_note}

Rules:
- Write CLEAN text (noise is added later programmatically). Do include the UI chrome words where OCR would catch them.
- CRITICAL anti-leakage rule: the screen must NOT contain the text the user should paste. Set up the need for a response; never include a model answer, a suggested reply, or the obvious paste content anywhere in screen_text, field_placeholder, or window title.
- Imperfect humans: occasional typos in other people's messages are good. Vary message lengths.
- Output ONLY the context block, nothing else."""


def sample_lang():
    r, acc = random.random(), 0.0
    for lang, w in LANGS:
        acc += w
        if r < acc:
            return lang
    return "English"


def build_scenario_prompts(n: int) -> list[dict]:
    cats = list(CATEGORIES.items())
    weights = [w for _, (w, _, _) in cats]
    prompts = []
    for _ in range(n):
        cat_name, (_, pool, directive) = random.choices(cats, weights=weights, k=1)[0]
        surf = SURFACES[random.choice(pool)]
        lang = sample_lang()
        length_pool = RESPONSE_LENGTH[:2] if cat_name in SHORT_ONLY_CATEGORIES else RESPONSE_LENGTH
        length_key, length_hint = random.choice(length_pool)
        register = ("the code/commands on screen follow whatever conventions the project shows"
                    if cat_name in NO_REGISTER_CATEGORIES else random.choice(FORMALITY))
        prompts.append({
            "category": cat_name,
            "length": length_key,
            "prompt": SCENARIO_PROMPT.format(
                app=surf["app"], window=surf["window"], field=surf["field"],
                chrome=surf["chrome"], directive=directive,
                domain=random.choice(DOMAINS),
                names=random.choice(NAME_STYLES),
                depth_line=("Conversation depth: " + random.choice(THREAD_DEPTH) + ".")
                           if cat_name in ("chat_reply", "continue_draft", "social_reply") else "",
                formality=register,
                length_hint=length_hint,
                lang=lang,
                lang_note="" if lang == "English" else
                          " The paste the user needs will be in that language too.",
            ),
        })
    return prompts


# ---------------------------------------------------------------------------
# Programmatic OCR noise (applied to screen_text only).
# Modeled on common Vision.framework failure modes on UI text.
# ---------------------------------------------------------------------------

CHAR_CONFUSIONS = [("m", "rn"), ("rn", "m"), ("l", "1"), ("1", "l"), ("O", "0"),
                   ("0", "O"), ("é", "e"), ("’", "'"), ("I", "l"), ("w", "vv")]


def inject_ocr_noise(screen_text: str, rng: random.Random) -> str:
    lines = screen_text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # ~7% of adjacent line pairs merge (column/row confusion)
        if i + 1 < len(lines) and rng.random() < 0.07:
            line = line.rstrip() + " " + lines[i + 1].lstrip()
            i += 1
        # ~10% of lines get one character confusion
        if line and rng.random() < 0.10:
            src, dst = rng.choice(CHAR_CONFUSIONS)
            if src in line:
                idx = line.index(src)
                line = line[:idx] + dst + line[idx + len(src):]
        # ~6% of lines lose one inner space
        if rng.random() < 0.06 and line.count(" ") > 2:
            spaces = [m.start() for m in re.finditer(" ", line)]
            cut = rng.choice(spaces[1:-1]) if len(spaces) > 2 else spaces[0]
            line = line[:cut] + line[cut + 1:]
        # ~3% of lines drop entirely (occlusion / low contrast)
        if rng.random() < 0.03 and len(lines) > 6:
            i += 1
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


CONTEXT_RE = re.compile(r"<context>.*?</context>", re.DOTALL)
SCREEN_RE = re.compile(r"(screen_text:\n)(.*?)(\n\[cursor is in the)", re.DOTALL)


def noise_context(ctx: str, rng: random.Random) -> str:
    m = SCREEN_RE.search(ctx)
    if not m:
        return ctx
    return ctx[:m.start()] + m.group(1) + inject_ocr_noise(m.group(2), rng) + m.group(3) + ctx[m.end():]


# ---------------------------------------------------------------------------
# Teacher + filtering
# ---------------------------------------------------------------------------

def call_claude(client, system, user, max_tokens=1400, retries=4) -> str:
    for attempt in range(retries):
        try:
            kwargs = dict(model=TEACHER_MODEL, max_tokens=max_tokens,
                          messages=[{"role": "user", "content": user}])
            if system:
                kwargs["system"] = system
            resp = client.messages.create(**kwargs)
            return resp.content[0].text.strip()
        except anthropic.RateLimitError:
            time.sleep(5 * (attempt + 1))
        except anthropic.APIStatusError:
            if attempt == retries - 1:
                raise
            time.sleep(3 * (attempt + 1))
    raise RuntimeError("exhausted retries")


PREAMBLE_RE = re.compile(r"^\s*(here('s| is)|sure|certainly|okay|of course)\b", re.I)


def bad_paste(paste: str, category: str) -> str | None:
    if not paste:
        return "empty"
    if "```" in paste:
        return "markdown_fence"
    if PREAMBLE_RE.match(paste):
        return "preamble"
    if paste.startswith('"') and paste.endswith('"') and category not in ("code", "terminal_command"):
        return "wrapped_quotes"
    if re.search(r"\bas an ai\b", paste, re.I):
        return "ai_disclaimer"
    return None


def extract_field_content(ctx: str) -> str:
    m = re.search(r"^field_content: (.*)$", ctx, re.M)
    return "" if not m or m.group(1).strip() == "(empty)" else m.group(1)


def make_example(client, scenario: dict, rng: random.Random) -> dict | None:
    ctx_raw = call_claude(client, None, scenario["prompt"])
    m = CONTEXT_RE.search(ctx_raw)
    if not m:
        return None
    ctx = noise_context(m.group(0), rng)
    paste = call_claude(client, SYSTEM_PROMPT, ctx, max_tokens=900)
    if bad_paste(paste, scenario["category"]):
        return None
    # continuation hygiene: paste must not restate the draft
    draft = extract_field_content(ctx)
    if draft and len(draft) > 12 and draft.strip()[:24].lower() in paste.lower():
        return None
    return {
        "category": scenario["category"],
        "length": scenario["length"],
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": ctx},
            {"role": "assistant", "content": paste},
        ],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=2000)
    ap.add_argument("--out", default="../data")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--seed", type=int, default=1337)
    args = ap.parse_args()

    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("Set ANTHROPIC_API_KEY first.")
    random.seed(args.seed)
    client = anthropic.Anthropic()
    os.makedirs(args.out, exist_ok=True)

    scenarios = build_scenario_prompts(args.n)
    examples, failed = [], 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = {ex.submit(make_example, client, s, random.Random(args.seed + i)): s
                   for i, s in enumerate(scenarios)}
        for i, fut in enumerate(as_completed(futures), 1):
            try:
                r = fut.result()
                if r:
                    examples.append(r)
                else:
                    failed += 1
            except Exception as e:
                failed += 1
                print(f"  error: {e}", file=sys.stderr)
            if i % 50 == 0:
                print(f"{i}/{len(scenarios)} done, {len(examples)} kept, {failed} rejected")

    random.shuffle(examples)
    n = len(examples)
    n_test = n_valid = max(50, n // 20)
    splits = {
        "test.jsonl": examples[:n_test],
        "valid.jsonl": examples[n_test:n_test + n_valid],
        "train.jsonl": examples[n_test + n_valid:],
    }
    for fname, rows in splits.items():
        with open(os.path.join(args.out, fname), "w") as f:
            for r in rows:
                f.write(json.dumps({"messages": r["messages"]}, ensure_ascii=False) + "\n")
        print(f"wrote {len(rows):5d} -> {fname}")
    with open(os.path.join(args.out, "meta.json"), "w") as f:
        json.dump([{"i": i, "category": e["category"], "length": e["length"]}
                   for i, e in enumerate(examples)], f)

    from collections import Counter
    print("\nCategory mix:", dict(Counter(e["category"] for e in examples)))
    print("Length mix:  ", dict(Counter(e["length"] for e in examples)))
    print(f"Total kept: {n} ({failed} rejected). Teacher: {TEACHER_MODEL}")


if __name__ == "__main__":
    main()
