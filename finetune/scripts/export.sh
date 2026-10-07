#!/usr/bin/env bash
# Export the fine-tuned SuperPaste model for distribution.
# Produces: (a) fused MLX 4-bit weights, (b) GGUF for llama.cpp.
set -euo pipefail

BASE_MODEL="${BASE_MODEL:-Qwen/Qwen3.5-2B-Instruct}"
ADAPTERS="${ADAPTERS:-../adapters}"
OUT_DIR="${OUT_DIR:-../dist}"
HF_REPO="${HF_REPO:-}"   # e.g. brainsparker/superpaste-2b  (optional upload)

mkdir -p "$OUT_DIR"

echo "==> 1/4 Fusing LoRA adapters into base weights (bf16)"
mlx_lm.fuse \
  --model "$BASE_MODEL" \
  --adapter-path "$ADAPTERS" \
  --save-path "$OUT_DIR/superpaste-fused" \
  --export-gguf --gguf-path "$OUT_DIR/superpaste-f16.gguf" || {
    echo "    (mlx_lm.fuse GGUF export unsupported for this arch; will use llama.cpp converter)"
    mlx_lm.fuse --model "$BASE_MODEL" --adapter-path "$ADAPTERS" \
      --save-path "$OUT_DIR/superpaste-fused"
  }

echo "==> 2/4 MLX 4-bit quantized copy (for MLX Swift runtime)"
mlx_lm.convert \
  --hf-path "$OUT_DIR/superpaste-fused" \
  --mlx-path "$OUT_DIR/superpaste-mlx-4bit" \
  -q --q-bits 4 --q-group-size 64

echo "==> 3/4 GGUF Q4_K_M (for llama.cpp runtime)"
if [ ! -f "$OUT_DIR/superpaste-f16.gguf" ]; then
  # Fallback path: use llama.cpp's converter on the fused HF-format weights
  if [ ! -d llama.cpp ]; then git clone --depth 1 https://github.com/ggml-org/llama.cpp; fi
  python3 llama.cpp/convert_hf_to_gguf.py "$OUT_DIR/superpaste-fused" \
    --outfile "$OUT_DIR/superpaste-f16.gguf" --outtype f16
fi
if [ ! -x llama.cpp/build/bin/llama-quantize ]; then
  cmake -S llama.cpp -B llama.cpp/build -DGGML_METAL=ON >/dev/null
  cmake --build llama.cpp/build --target llama-quantize -j >/dev/null
fi
llama.cpp/build/bin/llama-quantize \
  "$OUT_DIR/superpaste-f16.gguf" "$OUT_DIR/superpaste-q4_k_m.gguf" Q4_K_M

echo "==> 4/4 Sizes"
du -h "$OUT_DIR"/superpaste-q4_k_m.gguf "$OUT_DIR"/superpaste-mlx-4bit 2>/dev/null | sed 's/^/    /'

if [ -n "$HF_REPO" ]; then
  echo "==> Uploading to Hugging Face: $HF_REPO"
  pip -q install huggingface_hub
  hf upload "$HF_REPO" "$OUT_DIR/superpaste-q4_k_m.gguf"
  hf upload "$HF_REPO" "$OUT_DIR/superpaste-mlx-4bit" --include "*"
fi

echo "Done. Ship superpaste-q4_k_m.gguf (llama.cpp) or superpaste-mlx-4bit (MLX Swift)."
