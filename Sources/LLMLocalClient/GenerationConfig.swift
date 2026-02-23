/// テキスト生成の設定パラメータ
public struct GenerationConfig: Sendable {
    /// 生成する最大トークン数。
    public var maxTokens: Int
    /// サンプリング温度。値が高いほどランダムな出力になります。
    public var temperature: Float
    /// Top-p（核）サンプリングの閾値。
    public var topP: Float

    /// 新しい生成設定を作成します。
    /// - Parameters:
    ///   - maxTokens: 生成する最大トークン数。デフォルトは 1024。
    ///   - temperature: サンプリング温度。デフォルトは 0.7。
    ///   - topP: Top-p サンプリングの閾値。デフォルトは 0.9。
    public init(maxTokens: Int = 1024, temperature: Float = 0.7, topP: Float = 0.9) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
    }

    /// デフォルトの生成設定（maxTokens: 1024, temperature: 0.7, topP: 0.9）。
    public static let `default` = GenerationConfig()
}
