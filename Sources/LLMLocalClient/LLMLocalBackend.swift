import LLMTool

/// ローカルLLM推論バックエンドの抽象化プロトコル
///
/// 準拠する型は、モデルの読み込み・テキスト生成・モデルライフサイクル管理の機能を提供します。
/// すべての準拠型は並行アクセスをサポートするため `Sendable` である必要があります。
public protocol LLMLocalBackend: Sendable {
    /// 指定されたモデルをメモリに読み込み、推論可能な状態にします。
    /// - Parameter spec: 読み込むモデルを記述するモデル仕様。
    /// - Throws: モデルの読み込みに失敗した場合にエラーをスローします。
    func loadModel(_ spec: ModelSpec) async throws

    /// 指定されたモデルをメモリに読み込み、ダウンロード進捗を報告します。
    ///
    /// - Parameters:
    ///   - spec: 読み込むモデルを記述するモデル仕様。
    ///   - progressHandler: ダウンロード進捗の更新時に呼び出されるクロージャ。
    /// - Throws: モデルの読み込みに失敗した場合にエラーをスローします。
    func loadModel(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws

    /// 指定されたプロンプトからテキストを生成し、トークンをストリーミングで返します。
    /// - Parameters:
    ///   - prompt: 生成元の入力プロンプト。
    ///   - config: 生成を制御する設定パラメータ。
    /// - Returns: 生成されたトークン文字列の非同期ストリーム。
    func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error>

    /// ツール呼び出しをサポートしたレスポンスを生成し、出力チャンクをストリーミングで返します。
    ///
    /// 返されるストリームの各要素は、テキストチャンクまたはモデルが解析したツール呼び出しリクエストです。
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

    /// 現在読み込まれているモデルをアンロードし、メモリを解放します。
    func unloadModel() async

    /// モデルが現在読み込まれており推論可能かどうか。
    var isLoaded: Bool { get async }

    /// 現在読み込まれているモデルの仕様。モデルが読み込まれていない場合は `nil`。
    var currentModel: ModelSpec? { get async }

    /// 現在のシステムプロンプト。設定されていない場合は `nil`。
    var systemPrompt: String? { get async }

    /// 以降の生成に使用するシステムプロンプトを設定します。
    func setSystemPrompt(_ prompt: String?) async
}

// MARK: - System Prompt

extension LLMLocalBackend {
    /// デフォルト実装は `nil` を返します。
    public var systemPrompt: String? { nil }

    /// デフォルト実装は何も行いません。
    public func setSystemPrompt(_ prompt: String?) async {}
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

    /// ツールを無視し、各トークンを `.text` としてラップするデフォルト実装。
    public func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        let stream = generate(prompt: prompt, config: config)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await token in stream {
                        continuation.yield(.text(token))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
