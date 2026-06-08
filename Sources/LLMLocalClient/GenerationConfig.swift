/// テキスト生成の設定パラメータ。
///
/// MLX の `GenerateParameters` が持つツマミを一通り公開する。サンプリング
/// （temperature / topP / topK / minP / repetitionPenalty）に加え、メモリと
/// 速度に効く KV キャッシュ設定（kvBits / maxKVSize）と、思考モードの抑制
/// （enableThinking）を含む。
public struct GenerationConfig: Sendable, Hashable, Codable {
    // MARK: - Length

    /// 生成する最大トークン数。`nil` の場合はコンテキスト上限まで生成します。
    public var maxTokens: Int?

    // MARK: - Sampling

    /// サンプリング温度。低いほど決定的（ツールコール・構造化出力向き）。
    public var temperature: Float
    /// Top-p（核）サンプリングの閾値。
    public var topP: Float
    /// Top-k サンプリング。0 で無効。
    public var topK: Int
    /// Min-p サンプリング。0 で無効。
    public var minP: Float
    /// 繰り返しペナルティ。`nil` で無効。小型モデルのループ抑制に有効（1.05〜1.1 程度）。
    public var repetitionPenalty: Float?
    /// 繰り返しペナルティが参照する直近トークン数。
    public var repetitionContextSize: Int

    // MARK: - KV Cache（メモリ・長コンテキスト）

    /// KV キャッシュの量子化ビット数（4 / 8）。`nil` で非量子化。
    /// 長コンテキストのメモリを 2〜4 倍圧縮する。
    public var kvBits: Int?
    /// KV キャッシュの最大サイズ（トークン数）。`nil` で無制限。メモリ上限の歯止め。
    public var maxKVSize: Int?
    /// KV 量子化のグループサイズ。
    public var kvGroupSize: Int

    // MARK: - Prefill

    /// プリフィル（プロンプト処理）の 1 ステップあたりトークン数。
    public var prefillStepSize: Int

    // MARK: - Thinking

    /// 思考モード（Qwen3 系などの `<think>`）を有効にするか。
    /// `false` で空の思考ブロックを注入して思考生成を抑制し、レイテンシを大幅に削減する。
    /// エージェント（ツールコール）用途では `false` が高速。
    public var enableThinking: Bool

    public init(
        maxTokens: Int? = nil,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int = 0,
        minP: Float = 0,
        repetitionPenalty: Float? = nil,
        repetitionContextSize: Int = 20,
        kvBits: Int? = nil,
        maxKVSize: Int? = nil,
        kvGroupSize: Int = 64,
        prefillStepSize: Int = 512,
        enableThinking: Bool = true
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.repetitionPenalty = repetitionPenalty
        self.repetitionContextSize = repetitionContextSize
        self.kvBits = kvBits
        self.maxKVSize = maxKVSize
        self.kvGroupSize = kvGroupSize
        self.prefillStepSize = prefillStepSize
        self.enableThinking = enableThinking
    }

    /// 既定の生成設定。
    public static let `default` = GenerationConfig()
}
