import Foundation

/// ベースモデルの重みの所在を指定する列挙型
public enum ModelSource: Sendable, Hashable, Codable {
    /// Hugging Face Hub でホストされているモデル。
    /// - Parameter id: Hugging Face モデル識別子（例: "mlx-community/Llama-3.2-1B-Instruct-4bit"）。
    case huggingFace(id: String)

    /// ローカルファイルシステムに保存されたモデル。
    /// - Parameter path: モデルディレクトリを指すファイルURL。
    case local(path: URL)
}
