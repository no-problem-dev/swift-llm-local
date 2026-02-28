import Foundation
import LLMClient

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

    /// モデルの推定メモリ使用量（バイト単位）。
    ///
    /// 量子化後の推論時に必要なおおよそのメモリ量を示します。
    /// KV キャッシュやランタイムオーバーヘッドを含む概算値です。
    public let estimatedMemoryBytes: UInt64

    /// モデルの特性・能力プロファイル。
    ///
    /// ツールコール対応度、日本語力、量子化情報などを含みます。
    public let profile: ModelProfile?

    /// 新しいモデル仕様を作成します。
    /// - Parameters:
    ///   - id: このモデル仕様の一意識別子。
    ///   - base: ベースモデルの重みの所在。
    ///   - adapter: オプションの LoRA/QLoRA アダプター。デフォルトは `nil`。
    ///   - contextLength: トークン単位の最大コンテキスト長。
    ///   - displayName: 人間可読な表示名。
    ///   - description: モデルの人間可読な説明文。
    ///   - estimatedMemoryBytes: 推定メモリ使用量（バイト単位）。
    ///   - profile: モデルの特性プロファイル。デフォルトは `nil`。
    public init(
        id: String,
        base: ModelSource,
        adapter: AdapterSource? = nil,
        contextLength: Int,
        displayName: String,
        description: String,
        estimatedMemoryBytes: UInt64,
        profile: ModelProfile? = nil
    ) {
        self.id = id
        self.base = base
        self.adapter = adapter
        self.contextLength = contextLength
        self.displayName = displayName
        self.description = description
        self.estimatedMemoryBytes = estimatedMemoryBytes
        self.profile = profile
    }
}

extension ModelSpec {
    /// 推定メモリ使用量を人間可読な文字列で返します（例: "2.3 GB"）。
    public var formattedMemorySize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(estimatedMemoryBytes))
    }
}
