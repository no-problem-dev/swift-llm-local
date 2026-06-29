import Foundation

/// ``AdapterSource`` をローカルファイルURLに解決するプロトコル
///
/// Layer 2（MLXBackend）が Layer 1（AdapterRegistry）に直接依存せずに
/// アダプターソースを解決できるようにするプロトコル。
/// Layer 1 の型がこのプロトコルに準拠し、Layer 2 は依存性注入で受け取る。
///
/// ## Usage
///
/// ```swift
/// // AdapterRegistry（Layer 1）がこのプロトコルに準拠
/// let resolver: any AdapterResolving = adapterRegistry
///
/// // MLXBackend（Layer 2）は AdapterRegistry を知らずに使用可能
/// let backend = MLXBackend(adapterResolver: resolver)
/// ```
public protocol AdapterResolving: Sendable {
    /// アダプターソースをローカルファイルURLに解決する。
    ///
    /// ローカルソースの場合、パスの検証と返却のみを行う。
    /// リモートソース（GitHub Releases、HuggingFace）の場合、
    /// キャッシュされていなければアダプターをダウンロードする。
    ///
    /// - Parameter source: 解決するアダプターソース。
    /// - Returns: アダプターの重みファイルを指すローカルファイルURL。
    /// - Throws: アダプターの解決に失敗した場合（ダウンロード失敗、ファイル未検出など）。
    func resolve(_ source: AdapterSource) async throws -> URL
}
