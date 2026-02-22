#!/usr/bin/env python3
"""Prepare Japanese instruction data for Qwen3-4B LoRA fine-tuning.

Downloads kunishou/databricks-dolly-15k-ja from HuggingFace,
formats with Qwen3 chat template, and splits into train/valid/test JSONL files.
"""

import json
import random
from pathlib import Path

from datasets import load_dataset


DATA_DIR = Path(__file__).resolve().parent.parent / "data"

# Qwen3 chat template tokens
IM_START = "<|im_start|>"
IM_END = "<|im_end|>"


def format_chat(instruction: str, context: str, response: str) -> str:
    """Format a single example using Qwen3 chat template."""
    # Build user message
    if context and context.strip():
        user_content = f"{instruction}\n\n{context}"
    else:
        user_content = instruction

    return (
        f"{IM_START}system\nYou are a helpful assistant.{IM_END}\n"
        f"{IM_START}user\n{user_content}{IM_END}\n"
        f"{IM_START}assistant\n{response}{IM_END}\n"
    )


def main():
    random.seed(42)
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    print("Downloading kunishou/databricks-dolly-15k-ja ...")
    ds = load_dataset("kunishou/databricks-dolly-15k-ja", split="train")
    print(f"  Total examples: {len(ds)}")

    # Format all examples
    examples = []
    skipped = 0
    for row in ds:
        instruction = (row.get("instruction") or "").strip()
        response = (row.get("output") or "").strip()
        context = (row.get("input") or "").strip()

        if not instruction or not response:
            skipped += 1
            continue

        text = format_chat(instruction, context, response)
        examples.append({"text": text})

    print(f"  Valid examples: {len(examples)} (skipped {skipped})")

    # Shuffle and split 80/10/10
    random.shuffle(examples)
    n = len(examples)
    n_train = int(n * 0.8)
    n_valid = int(n * 0.1)

    train_data = examples[:n_train]
    valid_data = examples[n_train : n_train + n_valid]
    test_data = examples[n_train + n_valid :]

    # Write JSONL files
    for name, data in [("train", train_data), ("valid", valid_data), ("test", test_data)]:
        path = DATA_DIR / f"{name}.jsonl"
        with open(path, "w", encoding="utf-8") as f:
            for item in data:
                f.write(json.dumps(item, ensure_ascii=False) + "\n")
        print(f"  {name}: {len(data)} examples -> {path}")

    print("Done!")


if __name__ == "__main__":
    main()
