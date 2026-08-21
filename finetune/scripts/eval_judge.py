#!/usr/bin/env python3
"""
Eval harness: score the fine-tuned local model against the held-out test set,
using Claude as judge. Also scores the teacher itself so you have a ceiling.

Metrics per example (0-10 from the judge, plus hard checks):
  - relevance:   does the paste fit what the screen is asking for?
  - register:    tone/format matches the surface (Slack vs email vs code)?
  - paste_ready: hard check + judge; no preamble, no quotes, no fences,
                 no "As an AI", nothing the user must edit before sending.

Usage:
  # 1. Generate candidate outputs with the local model:
  python3 eval_judge.py generate --data ../data/test.jsonl \
      --model Qwen/Qwen3.5-2B-Instruct --adapter ../adapters --out ../data/candidates.jsonl

  # 2. Judge them (needs ANTHROPIC_API_KEY):
  python3 eval_judge.py judge --data ../data/test.jsonl \
      --candidates ../data/candidates.jsonl --report ../data/eval_report.json
"""

import argparse
import json
import os
import re
import statistics
import sys

JUDGE_MODEL = os.environ.get("JUDGE_MODEL", "claude-sonnet-4-5")

JUDGE_PROMPT = """You are evaluating a small local model that pastes text at a Mac user's cursor based on a screenshot's OCR context.

<context>
{context}
</context>

Candidate paste output:
<candidate>
{candidate}
</candidate>

Reference (what a frontier model pasted for the same context):
<reference>
{reference}
</reference>

Score the CANDIDATE (the reference is a guide, not ground truth; a different but equally good paste deserves full marks):
- relevance (0-10): does it correctly address what the screen needs at the cursor?
- register (0-10): tone, length, and format fit the surface (chat vs email vs code vs form field)?
- paste_ready (0-10): could it be pasted and sent as-is? Penalize preambles, explanations, surrounding quotes, markdown fences, placeholder brackets like [name].

Respond with ONLY a JSON object: {{"relevance": n, "register": n, "paste_ready": n, "note": "<one short sentence>"}}"""


def hard_checks(text: str) -> list[str]:
    problems = []
    if re.match(r"^\s*(here('s| is)|sure|certainly|okay|of course)\b", text, re.I):
        problems.append("preamble")
    if text.startswith('"') and text.endswith('"'):
        problems.append("wrapped_in_quotes")
    if "```" in text:
        problems.append("markdown_fence")
    if re.search(r"\bas an ai\b", text, re.I):
        problems.append("ai_disclaimer")
    if re.search(r"\[(your |insert |name|date)[^\]]*\]", text, re.I):
        problems.append("template_placeholder")
    return problems


def cmd_generate(args):
    from mlx_lm import load, generate
    model, tokenizer = load(args.model, adapter_path=args.adapter or None)
    rows = [json.loads(l) for l in open(args.data)]
    with open(args.out, "w") as f:
        for i, row in enumerate(rows):
            msgs = row["messages"][:2]  # system + user
            prompt = tokenizer.apply_chat_template(msgs, add_generation_prompt=True)
            out = generate(model, tokenizer, prompt=prompt, max_tokens=600, verbose=False)
            f.write(json.dumps({"candidate": out.strip()}, ensure_ascii=False) + "\n")
            if (i + 1) % 10 == 0:
                print(f"{i+1}/{len(rows)} generated")
    print(f"wrote {args.out}")


def cmd_judge(args):
    import anthropic
    client = anthropic.Anthropic()
    rows = [json.loads(l) for l in open(args.data)]
    cands = [json.loads(l) for l in open(args.candidates)]
    assert len(rows) == len(cands), "test set and candidates length mismatch"

    results = []
    for i, (row, cand) in enumerate(zip(rows, cands)):
        context = row["messages"][1]["content"]
        reference = row["messages"][2]["content"]
        candidate = cand["candidate"]
        hard = hard_checks(candidate)
        resp = client.messages.create(
            model=JUDGE_MODEL, max_tokens=300,
            messages=[{"role": "user", "content": JUDGE_PROMPT.format(
                context=context, candidate=candidate, reference=reference)}])
        m = re.search(r"\{.*\}", resp.content[0].text, re.DOTALL)
        scores = json.loads(m.group(0)) if m else {}
        scores["hard_failures"] = hard
        results.append(scores)
        if (i + 1) % 10 == 0:
            print(f"{i+1}/{len(rows)} judged")

    def avg(k):
        vals = [r[k] for r in results if isinstance(r.get(k), (int, float))]
        return round(statistics.mean(vals), 2) if vals else None

    report = {
        "n": len(results),
        "relevance_avg": avg("relevance"),
        "register_avg": avg("register"),
        "paste_ready_avg": avg("paste_ready"),
        "hard_failure_rate": round(
            sum(1 for r in results if r["hard_failures"]) / len(results), 3),
        "results": results,
    }
    with open(args.report, "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(json.dumps({k: v for k, v in report.items() if k != "results"}, indent=2))
    print(f"\nfull report -> {args.report}")
    print("\nShip gate suggestion: relevance >= 7.5, paste_ready >= 8.5, "
          "hard_failure_rate <= 0.02 before publishing weights.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate")
    g.add_argument("--data", required=True)
    g.add_argument("--model", required=True)
    g.add_argument("--adapter", default=None)
    g.add_argument("--out", required=True)
    j = sub.add_parser("judge")
    j.add_argument("--data", required=True)
    j.add_argument("--candidates", required=True)
    j.add_argument("--report", required=True)
    args = ap.parse_args()
    if args.cmd == "generate":
        cmd_generate(args)
    else:
        if not os.environ.get("ANTHROPIC_API_KEY"):
            sys.exit("Set ANTHROPIC_API_KEY first.")
        cmd_judge(args)
