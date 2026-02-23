import Foundation

/// モデルのソース・オプションアダプター・メタデータを含むモデル設定
public struct ModelSpec: Sendable, Hashable, Codable {
    /// このモデル仕様の一意識別子。
    public let id: String

    /// ベースモデルの重みの所在。
    public let base: ModelSource

    /// ベースモデルに適用するオプションの LoRA/QLoRA アダプター。
    public let adapter: AdapterSource?

    /// トークン単位の最大コンテキスト長。
    public let contextLength: Int

    /// 人間可読な表示名。
    public let displayName: String

    /// モデルの人間可読な説明文。
    public let description: String

    /// 新しいモデル仕様を作成します。
    /// - Parameters:
    ///   - id: このモデル仕様の一意識別子。
    ///   - base: ベースモデルの重みの所在。
    ///   - adapter: オプションの LoRA/QLoRA アダプター。デフォルトは `nil`。
    ///   - contextLength: トークン単位の最大コンテキスト長。
    ///   - displayName: 人間可読な表示名。
    ///   - description: モデルの人間可読な説明文。
    public init(
        id: String,
        base: ModelSource,
        adapter: AdapterSource? = nil,
        contextLength: Int,
        displayName: String,
        description: String
    ) {
        self.id = id
        self.base = base
        self.adapter = adapter
        self.contextLength = contextLength
        self.displayName = displayName
        self.description = description
    }
}
