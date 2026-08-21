---
license: apache-2.0
base_model: Qwen/Qwen3.5-2B-Instruct
language:
  - en
  - es
  - de
  - fr
  - pt
  - ja
pipeline_tag: text-generation
tags:
  - superpaste
  - on-device
  - macos
  - distillation
  - gguf
  - mlx
library_name: mlx
---

# superpaste-2b

**The local brain for [SuperPaste](https://github.com/brainsparker/superpaste).** Press Option+V on your Mac: SuperPaste captures the active window, reads it with on-device OCR (Apple Vision framework), and this model writes the text that belongs at your cursor. With the local model enabled, your screenshot never leaves your Mac.

- **Base model:** Qwen/Qwen3.5-2B-Instruct (Apache 2.0)
- **Fine-tuning:** LoRA (rank 16, attention projections, last 16 layers), trained with [MLX-LM](https://github.com/ml-explore/mlx-lm)
- **Formats:** GGUF Q4_K_M (~1.3GB, llama.cpp) and MLX 4-bit
- **Requirements:** Apple Silicon, 8GB RAM
- **License:** Apache 2.0 (weights), MIT (the SuperPaste app)

## What it does

One narrow task, done well: given a structured description of the active window, output exactly the text to paste. A Slack reply, an email, the next line of code, a form answer, the continuation of a half-typed draft. No preamble, no quotes, no markdown fences. The raw completion is pasted as-is.

## Input format

The model is trained on exactly the context block SuperPaste's Swift extractor produces at runtime. If you use this model outside SuperPaste, reproduce this format precisely; it is the contract (see [`finetune/SCHEMA.md`](https://github.com/brainsparker/superpaste/blob/main/finetune/SCHEMA.md)).

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

System prompt (fixed, baked into training):

```
You are SuperPaste, running locally on the user's Mac. You are given the
context of the active window. Write exactly the text that should be pasted
at the user's cursor. Match the register of the surrounding content: a
Slack reply is casual, an email is complete, code continues the file's
style. If field_content shows a partial draft, continue it from the cursor
without repeating any of it, joining cleanly. Output only the paste text.
Never explain, never wrap in quotes.
```

## Training data and provenance

Fully synthetic, distilled from a frontier teacher (Anthropic Claude). No user data, no scraped screenshots, no telemetry. The pipeline is open source in [`finetune/`](https://github.com/brainsparker/superpaste/tree/main/finetune):

1. **Scenario synthesis:** the teacher writes realistic window contexts across 13 app surfaces (Slack, Mail, Gmail, iMessage, Discord, VS Code, iTerm, Notion, Google Docs, Linear, X, browser forms, help desks), with sampled diversity axes: 30 subject-matter domains, 12 name-origin styles, 5 formality registers, thread depth, and target response length. An anti-leakage rule keeps the correct answer off the synthetic screen.
2. **Mechanical OCR noise:** character confusions, dropped spaces, merged and dropped lines are injected programmatically at rates modeled on Vision framework behavior, so training inputs match real OCR output.
3. **Teacher labeling:** the teacher answers the noised context under the exact system prompt above. Outputs with preambles, fences, wrapped quotes, or draft repetition are rejected.

Category mix: continue-a-draft 20%, chat replies 20%, email 15%, code and terminal 12%, on-screen Q&A 12%, forms 8%, rewrites 8%, social 5%, low-context conservatism 5%. About 85% English, the rest Spanish, German, French, Portuguese, and Japanese.

## Evaluation

Scored on a held-out synthetic test set by a frontier judge, plus hard format checks. Release gates for any published checkpoint:

| Metric | Gate | This release |
|---|---|---|
| Relevance (0-10) | >= 7.5 | TBD |
| Register match (0-10) | reported | TBD |
| Paste-readiness (0-10) | >= 8.5 | TBD |
| Hard format failure rate | <= 2% | TBD |

(TBD values are filled in from `eval_report.json` before each release; a checkpoint that misses a gate is not published.)

## How to run

**llama.cpp:**

```bash
llama-cli -m superpaste-q4_k_m.gguf --temp 0.3 -n 600 \
  -p "<system prompt>\n\n<context block>"
```

**MLX:**

```bash
pip install mlx-lm
mlx_lm.generate --model brainsparker/superpaste-2b-mlx-4bit \
  --prompt "<context block>" --max-tokens 600
```

Recommended sampling: temperature 0.3, top_p 0.9. Stop at the EOS token; the model emits only the paste text.

## Limitations

- Trained for the SuperPaste context format. Generic chat or instruction-following degrades outside it.
- Synthetic-only training data: real-world layouts the pipeline never imagined can produce off-target pastes. Review before sending anything consequential.
- Conservative by design when context is thin, but it can still guess wrong. It is a drafting tool, not an authority.
- Knowledge cutoff is inherited from the base model; it cannot look anything up.

## Privacy

Runs entirely on-device. SuperPaste's local mode sends nothing to any server: no screenshots, no OCR text, no telemetry. The Accessibility extractor never reads secure (password) fields.
