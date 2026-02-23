import Foundation

/// LoRA/QLoRA アダプターの所在を指定する列挙型
public enum AdapterSource: Sendable, Hashable, Codable {
    /// GitHub リリースアセットとして配布されるアダプター。
    /// - Parameters:
    ///   - repo: GitHub リポジトリ（例: "owner/repo"）。
    ///   - tag: リリースタグ（例: "v1.0"）。
    ///   - asset: アセットファイル名（例: "adapter.safetensors"）。
    case gitHubRelease(repo: String, tag: String, asset: String)

    /// Hugging Face Hub でホストされているアダプター。
    /// - Parameter id: Hugging Face モデル/アダプター識別子。
    case huggingFace(id: String)

    /// ローカルファイルシステムに保存されたアダプター。
    /// - Parameter path: アダプターディレクトリを指すファイルURL。
    case local(path: URL)
}
