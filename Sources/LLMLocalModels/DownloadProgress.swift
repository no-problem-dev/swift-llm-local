import Foundation
import LLMLocalClient

// MARK: - DownloadProgressDelegate

/// ダウンロード動作を注入するプロトコル（テスト用）
///
/// 実装は実際のダウンロード処理を行い、進行中にプログレスハンドラを呼び出す。
/// 戻り値はダウンロードされたモデルの合計サイズ（バイト単位）。
public protocol DownloadProgressDelegate: Sendable {
    /// `spec` で記述されたモデルをダウンロードし、`progressHandler` で進捗を報告する。
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
/// 実際のダウンロードが行われない場合のデフォルトデリゲート。
/// カスタムの ``DownloadProgressDelegate`` を注入することで動作を差し替えられる。
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
