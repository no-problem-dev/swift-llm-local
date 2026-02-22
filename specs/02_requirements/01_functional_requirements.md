---
title: "Functional Requirements"
created: 2026-02-22
status: draft
references:
  - ./00_index.md
---

# Functional Requirements

## FR-01: 推論バックエンド抽象化

### 概要
アプリが MLX に直接依存せず、Protocol 経由でローカル LLM 推論を利用できる。

### 要件

- **FR-01-1**: `LLMLocalBackend` プロトコルを定義する
  - モデルのロード（`loadModel`）
  - テキスト生成（`generate`）→ `AsyncThrowingStream<String, Error>` を返す
  - モデルのアンロード（`unloadModel`）
  - ロード状態の取得（`isLoaded`）
- **FR-01-2**: バックエンドは `actor` として実装し、スレッドセーフを保証する
- **FR-01-3**: `GenerationConfig` で生成パラメータ（maxTokens, temperature, topP）を制御できる
  - Note: mlx-swift-lm が対応するパラメータに依存。Phase 1 開始前に実際の API を検証すること
- **FR-01-4**: 生成を途中キャンセルできる（Task cancellation 対応）

### 完了条件
- `LLMLocalBackend` プロトコルに準拠した MLX 実装が動作する
- Protocol のみに依存するテストコードが記述可能（MockBackend）

---

## FR-02: MLX バックエンド実装

### 概要
mlx-swift-lm を使った `LLMLocalBackend` の具体実装。

### 要件

- **FR-02-1**: `MLXBackend: LLMLocalBackend` を actor として実装する
- **FR-02-2**: `ModelSpec` から HuggingFace モデル ID を解決し、mlx-swift-lm の API でロードする
- **FR-02-3**: `ChatSession` をラップし、ストリーミング生成を `AsyncThrowingStream` で提供する
- **FR-02-4**: GPU キャッシュサイズを設定可能にする（`MLX.GPU.set(cacheLimit:)`）
- **FR-02-5**: ロード中の二重呼び出しを排他制御する（`LLMLocalError.loadInProgress`）

### 前提条件（Phase 1 開始前に検証）
- mlx-swift-lm の `ChatSession.streamResponse(to:)` の正確な型シグネチャを確認
- mlx-swift-lm の生成パラメータ（temperature, maxTokens 等）の指定方法を確認
- iOS Sandbox でのキャッシュパスが正しく動作するか確認

### 完了条件
- HuggingFace 上の MLX 量子化モデル（Gemma 2B 等の軽量モデル）をロードし、ストリーミング生成が動作する

---

## FR-03: モデル定義・管理

### 概要
アプリが利用するモデルを型安全に定義し、ダウンロード・キャッシュを管理する。

### 要件

- **FR-03-1**: `ModelSpec` 型でモデルを定義する
  - `id`: 一意な識別子（アプリ内で使用）
  - `base`: ベースモデルのソース（HuggingFace ID）
  - `adapter`: オプショナルな LoRA アダプターソース（Phase 2）
  - `contextLength`: 最大コンテキスト長
  - `displayName`: アプリ表示用の名前
  - `description`: モデルの説明
- **FR-03-2**: `ModelSource` enum でモデルの取得先を表現する
  - `.huggingFace(id: String)`: HuggingFace リポジトリ
  - `.local(path: URL)`: ローカルファイルパス
- **FR-03-3**: `AdapterSource` enum でアダプターの取得先を表現する（Phase 2）
  - `.gitHubRelease(repo: String, tag: String, asset: String)`: GitHub Releases
  - `.huggingFace(id: String)`: HuggingFace リポジトリ
  - `.local(path: URL)`: ローカルファイルパス
- **FR-03-4**: 推奨モデルのプリセット定義を提供する（`ModelPresets`）

### 完了条件
- `ModelSpec` を定義し、バックエンドに渡してモデルをロードできる
- プリセットから簡単にモデルを選択できる

---

## FR-04: モデルダウンロード・キャッシュ

### 概要
モデルファイルのダウンロード、キャッシュ管理、ストレージ管理を行う。

### 要件

- **FR-04-1**: `ModelManager` actor を提供する
- **FR-04-2**: HuggingFace からのモデルダウンロードに対応する（mlx-swift-lm の Hub 統合を活用し、`ModelManager` はキャッシュ状態の監視・管理を行う）
- **FR-04-3**: ダウンロード済みモデルの一覧を取得できる
- **FR-04-4**: モデルのキャッシュを削除できる
- **FR-04-5**: キャッシュ済みかどうかを判定できる（再ダウンロード不要の判定）
- **FR-04-6**: ダウンロード進捗を `AsyncThrowingStream<DownloadProgress, Error>` で通知する（Phase 2）
- **FR-04-7**: ダウンロードのレジューム対応（Phase 3）

### 完了条件
- モデルをダウンロードし、キャッシュから再ロードできる
- キャッシュの一覧取得・削除が動作する

---

## FR-05: ストリーミング生成

### 概要
トークン単位でのストリーミング出力を提供する。

### 要件

- **FR-05-1**: `AsyncThrowingStream<String, Error>` でトークンを逐次返す
- **FR-05-2**: 生成統計（トークン数、速度 tok/s、所要時間）を `GenerationStats` で取得できる
  - `LLMLocalService.lastGenerationStats` プロパティで直近の統計を取得
- **FR-05-3**: `Task.cancel()` で生成を中断できる
  - キャンセル後もモデルセッションは有効（即座に次の生成が可能）
  - `continuation.onTermination` で Task をキャンセル

### 完了条件
- `for try await token in ...` でリアルタイムにトークンを受信できる
- キャンセル時にリソースが適切に解放される
- 生成完了後に統計情報が取得できる

---

## FR-06: LoRA アダプター管理（Phase 2）

### 概要
ファインチューニング済みアダプターをベースモデルに合成してロードする。

### 要件

- **FR-06-1**: GitHub Releases からアダプターファイルをダウンロードする
- **FR-06-2**: ベースモデル + アダプターを合成してロードする（MLX Backend 内で実装）
- **FR-06-3**: アダプターのバージョン管理（tag ベース）に対応する
- **FR-06-4**: アダプターなしの `ModelSpec` と同一の API で利用できる
- **FR-06-5**: ベースモデルとアダプターの互換性チェックを行う

### 完了条件
- ベースモデル（HuggingFace Hub）+ アダプター（GitHub Releases）の組み合わせで推論が動作する

---

## FR-07: メモリ管理（Phase 2）

### 概要
iPhone のメモリ制約下でモデルのライフサイクルを安全に管理する。

### 要件

- **FR-07-1**: 現在のメモリ使用量を監視できる
- **FR-07-2**: メモリ警告（`didReceiveMemoryWarning`）に応じてモデルをアンロードできる
- **FR-07-3**: コンテキスト長の上限をモデルロード時に設定できる
  - iPhone 16 Pro（8GB）: デフォルト 2048 トークン
  - iPhone 17 Pro（12GB）: デフォルト 4096 トークン

### 完了条件
- メモリ警告時にモデルが安全にアンロードされる
- OOM kill が発生しない
