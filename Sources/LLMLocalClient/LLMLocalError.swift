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
}
