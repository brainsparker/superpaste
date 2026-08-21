# SuperPaste Local Model: Fine-Tuning Starter Kit

Everything needed to train, evaluate, and ship an open-source small language model that runs SuperPaste fully on-device: hotkey → screenshot → Vision OCR → local SLM → paste.

See the full playbook for reasoning and tradeoffs. Quick path:

```bash
# 0. Prereqs: Apple Silicon Mac, Python 3.10+, ANTHROPIC_API_KEY
pip install mlx-lm anthropic

# 1. Generate distillation data (Claude is the teacher). Start small.
cd scripts
python3 generate_dataset.py --n 200 --out ../data   # inspect quality first
python3 generate_dataset.py --n 2000 --out ../data  # real run

# 2. Fine-tune with LoRA (about 1-3 hours on an M-series Mac for a 2B base)
mlx_lm.lora --config lora_config.yaml

# 3. Evaluate against the held-out test set with Claude as judge
python3 eval_judge.py generate --data ../data/test.jsonl \
  --model Qwen/Qwen3.5-2B-Instruct --adapter ../adapters --out ../data/candidates.jsonl
python3 eval_judge.py judge --data ../data/test.jsonl \
  --candidates ../data/candidates.jsonl --report ../data/eval_report.json

# 4. Export for distribution (MLX 4-bit + GGUF Q4_K_M), optionally push to HF
HF_REPO=brainsparker/superpaste-2b ./export.sh
```

## Layout

| Path | What it is |
|---|---|
| `SCHEMA.md` | The contract: exact input/output format shared by training data and the Swift runtime |
| `scripts/generate_dataset.py` | Synthesizes screen scenarios and distills paste targets from Claude into JSONL |
| `scripts/lora_config.yaml` | MLX-LM LoRA training config (Qwen3.5-2B default) |
| `scripts/eval_judge.py` | Generates candidates with the tuned model, scores them with Claude as judge |
| `scripts/export.sh` | Fuse adapters, quantize, convert to GGUF and MLX 4-bit, upload to Hugging Face |
| `swift/ContextExtractor.swift` | On-device Vision OCR + Accessibility context extractor matching SCHEMA.md |

## The one rule

Training input format and runtime input format must be identical. `SCHEMA.md` is the contract; `generate_dataset.py` and `ContextExtractor.swift` both implement it. If you change one, change all three.

## Ship gate

Before publishing weights: relevance >= 7.5, paste_ready >= 8.5, hard failure rate <= 2% on the held-out set. Compare against the teacher's own scores to know your ceiling.
