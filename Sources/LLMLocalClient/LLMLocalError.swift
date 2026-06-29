import Foundation

/// ローカルLLM操作で発生しうるエラー
public enum LLMLocalError: Error, Sendable, Equatable {
    /// モデルのダウンロードに失敗。
    /// - Parameters:
    ///   - modelId: ダウンロードに失敗したモデルの識別子。
    ///   - reason: 失敗の人間可読な説明。
    case downloadFailed(modelId: String, reason: String)

    /// モデルの読み込みに失敗。
    /// - Parameters:
    ///   - modelId: 読み込みに失敗したモデルの識別子。
    ///   - reason: 失敗の人間可読な説明。
    case loadFailed(modelId: String, reason: String)

    /// モデルの読み込みに必要なデバイスメモリが不足。
    /// - Parameters:
    ///   - required: 必要なバイト数。
    ///   - available: 利用可能なバイト数。
    case insufficientMemory(required: Int, available: Int)

    /// モデルのダウンロードに必要なストレージが不足。
    /// - Parameters:
    ///   - required: 必要なバイト数。
    ///   - available: 利用可能なバイト数。
    case insufficientStorage(required: Int64, available: Int64)

    /// モデルが読み込まれていない。
    case modelNotLoaded

    /// モデルの読み込み操作が既に進行中。
    case loadInProgress

    /// 操作がキャンセルされた。
    case cancelled

    /// LoRA/QLoRA アダプターのマージに失敗。
    /// - Parameter reason: 失敗の人間可読な説明。
    case adapterMergeFailed(reason: String)

    /// サポートされていないモデル形式。
    /// - Parameter format: サポートされていない形式の説明。
    case unsupportedModelFormat(String)

    /// ツールコール非対応のモデルにツールが渡された。
    ///
    /// ツールを黙って無視すると、エージェントループが「ツール不要」と
    /// 誤解釈してターンを終了してしまうため、明示的にエラーにする。
    /// - Parameter modelId: ツールコール非対応のモデルの識別子。
    case toolCallsUnsupported(modelId: String)
}

// MARK: - LocalizedError

extension LLMLocalError: LocalizedError {
    /// 人間可読なエラー説明。
    ///
    /// `LocalizedError` 未準拠だと `localizedDescription` が
    /// "...LLMLocalError error N." という不透明な文言になり、`reason` 等の
    /// associated value が握り潰される。各ケースの内容を文言に展開する。
    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let modelId, let reason):
            "モデル '\(modelId)' のダウンロードに失敗しました: \(reason)"
        case .loadFailed(let modelId, let reason):
            "モデル '\(modelId)' の読み込みに失敗しました: \(reason)"
        case .insufficientMemory(let required, let available):
            "メモリ不足です（必要: \(required) バイト / 利用可能: \(available) バイト）"
        case .insufficientStorage(let required, let available):
            "ストレージ不足です（必要: \(required) バイト / 利用可能: \(available) バイト）"
        case .modelNotLoaded:
            "モデルが読み込まれていません"
        case .loadInProgress:
            "モデルの読み込みが既に進行中です"
        case .cancelled:
            "操作がキャンセルされました"
        case .adapterMergeFailed(let reason):
            "アダプターのマージに失敗しました: \(reason)"
        case .unsupportedModelFormat(let format):
            "サポートされていないモデル形式です: \(format)"
        case .toolCallsUnsupported(let modelId):
            "モデル '\(modelId)' はツールコールに対応していません"
        }
    }
}
