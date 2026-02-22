#!/usr/bin/env bash
# QLoRA fine-tuning for Qwen3-4B-Instruct-2507
#
# Uses 4-bit quantized model (QLoRA) to fit within M3 16GB memory.
# Model ~2.3GB + training ~2-3GB = ~5GB total.
#
# Prerequisites:
#   pip install -r requirements.txt
#   python scripts/01_prepare_data.py
#
# Estimated time: ~1-2 hours on M3 16GB

set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="mlx-community/Qwen3-4B-Instruct-2507-4bit"
DATA_DIR="./data"
ADAPTER_PATH="./output/adapters"
CONFIG_PATH="./lora_config.yaml"

# Create LoRA config with rank setting
cat > "${CONFIG_PATH}" <<EOF
lora_parameters:
  rank: 8
  alpha: 16
  dropout: 0.0
  scale: 10.0
EOF

echo "=== QLoRA Training ==="
echo "Model: ${MODEL}"
echo "Data:  ${DATA_DIR}"
echo "Output: ${ADAPTER_PATH}"
echo ""

python -m mlx_lm lora \
  --model "${MODEL}" \
  --data "${DATA_DIR}" \
  --train \
  --batch-size 1 \
  --num-layers 16 \
  --iters 1000 \
  --learning-rate 1e-5 \
  --steps-per-report 10 \
  --steps-per-eval 100 \
  --val-batches 10 \
  --save-every 200 \
  --adapter-path "${ADAPTER_PATH}" \
  --config "${CONFIG_PATH}" \
  --grad-checkpoint

echo ""
echo "=== Training complete ==="
echo "Adapters saved to: ${ADAPTER_PATH}"
