#!/usr/bin/env bash
# Fuse LoRA adapters into the 4-bit base model.
#
# QLoRA approach: adapters trained on 4-bit model are fused back into it.
# The result is already 4-bit quantized and ready for deployment.
#
# Prerequisites:
#   bash scripts/02_train_lora.sh
#
# Output: ./output/fused_4bit/ (ready for HuggingFace upload)

set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="mlx-community/Qwen3-4B-Instruct-2507-4bit"
ADAPTER_PATH="./output/adapters"
FUSED_4BIT="./output/fused_4bit"

echo "=== Fuse LoRA adapters into 4-bit base ==="
echo "Base model: ${MODEL}"
echo "Adapters:   ${ADAPTER_PATH}"
echo "Output:     ${FUSED_4BIT}"
echo ""

python -m mlx_lm fuse \
  --model "${MODEL}" \
  --adapter-path "${ADAPTER_PATH}" \
  --save-path "${FUSED_4BIT}"

echo ""
echo "=== Done ==="
echo "Fused 4-bit model: ${FUSED_4BIT}"
echo ""
echo "Verify model size:"
du -sh "${FUSED_4BIT}"
echo ""
echo "Next steps:"
echo "  1. Test locally:"
echo "     python -m mlx_lm generate --model ${FUSED_4BIT} --prompt '日本の首都はどこですか？'"
echo "  2. Upload to HuggingFace:"
echo "     huggingface-cli upload noproblem-io/Qwen3-4B-Instruct-2507-ja-4bit ${FUSED_4BIT} ."
