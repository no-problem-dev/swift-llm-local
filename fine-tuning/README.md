# Qwen3-4B 日本語 LoRA ファインチューニング

Qwen3-4B-Instruct-2507 をベースに日本語 instruction データで LoRA ファインチューニングし、
4bit 量子化して iPhone にデプロイするためのパイプライン。

## 前提条件

- Apple Silicon Mac (M1 以上、16GB RAM 推奨)
- Python 3.10+

## セットアップ

```bash
cd fine-tuning
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 実行手順

### 1. データ準備

```bash
python scripts/01_prepare_data.py
```

`kunishou/databricks-dolly-15k-ja` をダウンロードし、Qwen3 の chat template でフォーマット。
80/10/10 で train/valid/test に分割し、`data/` に JSONL で保存。

### 2. LoRA 学習

```bash
bash scripts/02_train_lora.sh
```

MLX-LM の LoRA trainer で学習。M3 16GB で約 1-2 時間。

### 3. マージ + 量子化

```bash
bash scripts/03_fuse_and_quantize.sh
```

LoRA アダプタをベースモデルにマージし、4bit 量子化。

### 4. 品質確認

```bash
python -m mlx_lm.generate \
  --model ./output/fused_4bit \
  --prompt "日本の首都はどこですか？"
```

## デプロイ戦略: Fused Model (Strategy A)

LoRA をベースモデルにマージ → 4bit 量子化 → スタンドアロンモデルとしてデプロイ。

1. `output/fused_4bit` を HuggingFace にアップロード
2. Swift パッケージの `ModelPresets.qwen3_4B_ja` プリセットで参照
3. サンプルアプリでダウンロード・実行

## ディレクトリ構造

```
fine-tuning/
├── README.md
├── requirements.txt
├── scripts/
│   ├── 01_prepare_data.py    # データ準備
│   ├── 02_train_lora.sh      # LoRA 学習
│   └── 03_fuse_and_quantize.sh  # マージ + 量子化
├── data/                     # .gitignore 対象
└── output/                   # .gitignore 対象
```
