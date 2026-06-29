import LLMClient
import LLMTool

/// ローカル LLM 推論バックエンドの抽象化プロトコル
///
/// 準拠する型はモデルの読み込み・テキスト生成・モデルライフサイクル管理の機能を提供する。
/// すべての準拠型は並行アクセスをサポートするため `Sendable` である必要がある。
public protocol LLMLocalBackend: Sendable {
    /// 指定されたモデルをメモリに読み込み、推論可能な状態にする。
    /// - Parameter spec: 読み込むモデルを記述するモデル仕様。
    /// - Throws: モデルの読み込みに失敗した場合。
    func loadModel(_ spec: ModelSpec) async throws

    /// 指定されたモデルをメモリに読み込み、ダウンロード進捗を報告する。
    ///
    /// - Parameters:
    ///   - spec: 読み込むモデルを記述するモデル仕様。
    ///   - progressHandler: ダウンロード進捗の更新時に呼び出されるクロージャ。
    /// - Throws: モデルの読み込みに失敗した場合。
    func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws

    /// 指定されたプロンプトからテキストを生成し、トークンをストリーミングで返す。
    /// - Parameters:
    ///   - prompt: 生成元の入力プロンプト。
    ///   - config: 生成を制御する設定パラメータ。
    /// - Returns: 生成されたトークン文字列の非同期ストリーム。
    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error>

    /// ツール呼び出しをサポートしたレスポンスを生成し、出力チャンクをストリーミングで返す。
    ///
    /// ストリームの各要素はテキストチャンクまたはモデルが解析したツール呼び出しリクエスト。
    /// - Parameters:
    ///   - prompt: 生成元の入力プロンプト。
    ///   - config: 生成を制御する設定パラメータ。
    ///   - tools: モデルが使用可能なツール定義。
    /// - Returns: ``GenerationOutput`` 値の非同期ストリーム。
    func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error>

    /// 現在読み込まれているモデルをアンロードし、メモリを解放する。
    func unloadModel() async

    /// モデルが現在読み込まれており推論可能かどうか。
    var isLoaded: Bool { get async }

    /// 現在読み込まれているモデルの仕様。モデルが読み込まれていない場合は `nil`。
    var currentModel: ModelSpec? { get async }

    /// 現在のシステムプロンプト。設定されていない場合は `nil`。
    var systemPrompt: String? { get async }

    /// 以降の生成に使用するシステムプロンプトを設定する。
    func setSystemPrompt(_ prompt: String?) async

    /// チャットセッションの会話履歴をリセットする。
    ///
    /// モデルは読み込まれたまま保持し、会話のみをクリアする。新しい会話を開始する際に使用する。
    func resetSession() async

    /// 構造化メッセージ配列からレスポンスを生成する。
    ///
    /// チャットテンプレートは内部で 1 回だけ適用される。
    /// `MessageFormatter` 等で事前フォーマット + `ChatSession` の二重テンプレート適用を回避するための API。
    ///
    /// - Parameters:
    ///   - messages: 会話履歴のメッセージ配列。
    ///   - systemPrompt: システムプロンプト（オプション）。
    ///   - config: 生成を制御する設定パラメータ。
    ///   - tools: モデルが使用可能なツール定義。
    /// - Returns: ``GenerationOutput`` 値の非同期ストリーム。
    func generateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error>
}

// MARK: - System Prompt

extension LLMLocalBackend {
    /// デフォルト実装は `nil` を返す。
    public var systemPrompt: String? { nil }

    /// デフォルト実装は何も行わない。
    public func setSystemPrompt(_ prompt: String?) async {}

    /// デフォルト実装は何も行わない。
    public func resetSession() async {}
}

// MARK: - Default Implementation

extension LLMLocalBackend {
    /// プログレスハンドラを無視し、`loadModel(_:)` に委譲するデフォルト実装。
    public func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        try await loadModel(spec)
    }

    /// ツールコール非対応バックエンドのデフォルト実装。
    ///
    /// ツールが渡された場合は ``LLMLocalError/toolCallsUnsupported(modelId:)`` で失敗する。
    /// ツールを黙って捨てると呼び出し側が「ツール不要の応答」と誤解釈するためエラーにする。
    /// ツールが空の場合は `generate` に委譲し、各トークンを `.text` としてラップする。
    public func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        guard tools.isEmpty else {
            return makeCancellableStream { continuation in
                Task {
                    let modelId = await currentModel?.id ?? "unknown"
                    continuation.finish(throwing: LLMLocalError.toolCallsUnsupported(modelId: modelId))
                }
            }
        }
        let stream = generate(prompt: prompt, config: config)
        return makeCancellableStream { continuation in
            Task {
                do {
                    for try await token in stream {
                        try Task.checkCancellation()
                        continuation.yield(.text(token))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// メッセージをテキストに結合して `generateWithTools` に委譲するデフォルト実装。
    public func generateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        let prompt = messages.map { $0.content }.joined(separator: "\n")
        return generateWithTools(prompt: prompt, config: config, tools: tools)
    }
}
