import Foundation
import LLMLocalClient

// MARK: - DownloadProgressDelegate

/// ダウンロード動作を注入するプロトコル（テスト用）
///
/// 実装は実際のダウンロード処理を行い、進行中にプログレスハンドラを呼び出します。
/// 戻り値はダウンロードされたモデルの合計サイズ（バイト単位）です。
public protocol DownloadProgressDelegate: Sendable {
    /// `spec` で記述されたモデルをダウンロードし、`progressHandler` で進捗を報告します。
    ///
    /// - Parameters:
    ///   - spec: ダウンロードするモデル仕様。
    ///   - progressHandler: ダウンロード中に進捗更新で呼び出されるクロージャ。
    /// - Returns: ダウンロードされたモデルの合計サイズ（バイト単位）。
    /// - Throws: ダウンロード中に発生したエラー。
    func download(
        _ spec: ModelSpec,
        progressHandler: @Sendable (DownloadProgress) -> Void
    ) async throws -> Int64
}

// MARK: - StubDownloadDelegate

/// ネットワークアクセスなしで完了済みダウンロードをシミュレートするデフォルトスタブデリゲート
///
/// Phase 2 のスタブです。将来のフェーズで実際の HuggingFace Hub
/// ダウンロード統合に置き換えられます。
struct StubDownloadDelegate: DownloadProgressDelegate {
    /// スタブダウンロードが返す固定サイズ。
    static let stubSize: Int64 = 1_000_000

    func download(
        _ spec: ModelSpec,
        progressHandler: @Sendable (DownloadProgress) -> Void
    ) async throws -> Int64 {
        StubDownloadDelegate.stubSize
    }
}
