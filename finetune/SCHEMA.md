# SuperPaste SLM Task Schema

The single most important rule of this project: **the model is trained on exactly the input format the app produces at runtime.** Same OCR engine, same field order, same truncation rules. Any drift between training and runtime input distribution costs more quality than any hyperparameter.

## Input (user message)

The Swift context extractor produces this structured block from the active window:

```
<context>
app: Slack
window: #product-eng | Acme Inc
focused_field: message input
field_placeholder: Message #product-eng
field_content: (empty)
selected_text: (none)
screen_text:
Jordan Kim  10:42 AM
Hey, did the migration finish last night? Dashboard still shows the old counts.
Priya N  10:44 AM
I saw the job complete in Airflow but haven't verified the tables.
[cursor is in the message input]
</context>
```

Field definitions:

| Field | Source | Notes |
|---|---|---|
| `app` | `NSWorkspace.frontmostApplication` | Localized name |
| `window` | Accessibility API (`kAXTitleAttribute`) | Window title |
| `focused_field` | Accessibility API (`kAXFocusedUIElement` role + label) | e.g. "message input", "email body", "search field", "code editor" |
| `field_placeholder` | `kAXPlaceholderValueAttribute` | Empty string if none |
| `field_content` | `kAXValueAttribute` of the focused element | Text already typed in the field. "(empty)" if none. Max 1000 chars, truncate from the top. When non-empty, the correct paste usually CONTINUES this draft from the cursor: no repetition of what's already typed, and it must join cleanly (leading space or not, matching case) |
| `selected_text` | `kAXSelectedTextAttribute` | "(none)" if empty |
| `screen_text` | Vision framework OCR (`VNRecognizeTextRequest`, `.accurate`) | Top-to-bottom, left-to-right reading order. Lines joined with `\n`. Max 3000 chars, truncate from the TOP (recent content at the bottom of a window matters most) |

## Output (assistant message)

**The paste string and nothing else.** No preamble, no quotes, no markdown fences, no "Here's a response:". The app pastes the raw completion at the cursor. Format compliance is a first-class training objective and a first-class eval metric.

## System prompt (fixed, baked into training data)

```
You are SuperPaste, running locally on the user's Mac. You are given the
context of the active window. Write exactly the text that should be pasted
at the user's cursor. Match the register of the surrounding content: a
Slack reply is casual, an email is complete, code continues the file's
style. If field_content shows a partial draft, continue it from the cursor
without repeating any of it, joining cleanly. Output only the paste text.
Never explain, never wrap in quotes.
```

## Training pair format (chat JSONL, MLX-LM `chat` format)

```json
{"messages": [
  {"role": "system", "content": "<fixed system prompt>"},
  {"role": "user", "content": "<context>...</context>"},
  {"role": "assistant", "content": "Job finished at 2:14 AM and the Airflow run is green. I'll verify the table counts now and post here once the dashboard refreshes."}
]}
```

## Scenario coverage targets (for the synthetic generator)

Aim for rough balance across these categories, since the runtime distribution is unknown at launch:

- Continue a half-typed draft (`field_content` non-empty, any surface): 20%
- Chat replies (Slack, Discord, iMessage, Teams): 20%
- Email (compose, reply, follow-up): 15%
- Code continuation and terminal commands (editors, terminals): 12%
- Answers to on-screen questions (docs, quizzes, support tickets): 12%
- Forms and fields (search queries, form fills, titles): 8%
- Rewrites of selected text (when `selected_text` is present): 8%
- Social replies (X, LinkedIn comments): 5%
- Low-context cases where the right paste is minimal or conservative: 5%

Also vary: OCR noise (dropped characters, merged lines, timestamps, UI chrome text bleeding in), window title formats, multilingual snippets, and very long vs. very short screen_text.
