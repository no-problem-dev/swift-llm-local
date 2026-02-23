import Foundation

/// ``AdapterSource`` をローカルファイルURLに解決するプロトコル
///
/// Layer 2（MLXBackend）が Layer 1（AdapterManager）に直接依存せずに
/// アダプターソースを解決できるようにするプロトコルです。
/// Layer 1 の型がこのプロトコルに準拠し、Layer 2 は依存性注入で受け取ります。
///
/// ## Usage
///
/// ```swift
/// // AdapterManager（Layer 1）がこのプロトコルに準拠
/// let resolver: any AdapterResolving = adapterManager
///
/// // MLXBackend（Layer 2）は AdapterManager を知らずに使用可能
/// let backend = MLXBackend(adapterResolver: resolver)
/// ```
public protocol AdapterResolving: Sendable {
    /// アダプターソースをローカルファイルURLに解決します。
    ///
    /// ローカルソースの場合、パスの検証と返却のみを行います。
    /// リモートソース（GitHub Releases、HuggingFace）の場合、
    /// キャッシュされていなければアダプターをダウンロードします。
    ///
    /// - Parameter source: 解決するアダプターソース。
    /// - Returns: アダプターの重みファイルを指すローカルファイルURL。
    /// - Throws: アダプターの解決に失敗した場合（ダウンロード失敗、ファイル未検出など）。
    func resolve(_ source: AdapterSource) async throws -> URL
}
