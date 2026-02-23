import Foundation
import LLMLocalClient

// MARK: - DownloadState

/// バックグラウンドダウンロードの追跡に使用する内部状態
public enum DownloadState: Sendable {
    /// ダウンロードが進行中。
    case downloading

    /// レジュームデータを保存してダウンロードが一時停止中。
    case paused(resumeData: Data)

    /// ダウンロードが正常に完了。
    case completed(localURL: URL)

    /// ダウンロードがエラーで失敗。
    case failed(error: any Error)
}

// MARK: - BackgroundDownloadError

/// バックグラウンドダウンロード操作固有のエラー
public enum BackgroundDownloadError: Error, Sendable, Equatable {
    /// 要求されたURLのレジュームデータが存在しない。
    case noResumeData

    /// 要求されたURLは現在ダウンロード中ではない。
    case notDownloading

    /// レジュームデータの永続化に失敗。
    case resumeDataPersistenceFailed(reason: String)
}

// MARK: - BackgroundDownloadDelegate

/// バックグラウンドダウンロード操作のプロトコル
///
/// テスト用の依存性注入を可能にします。実装は実際の URLSession
/// バックグラウンドダウンロード動作またはテストスタブを提供します。
public protocol BackgroundDownloadDelegate: Sendable {
    /// バックグラウンドダウンロードを開始または再開します。
    ///
    /// - Parameters:
    ///   - url: ダウンロード元のリモートURL。
    ///   - resumeData: 以前一時停止したダウンロードからのレジュームデータ（オプション）。
    /// - Returns: ダウンロードが保存されたローカルファイルURL。
    /// - Throws: ダウンロード中に発生したエラー。
    func startDownload(url: URL, resumeData: Data?) async throws -> URL

    /// 指定されたURLのダウンロードが再開可能かを確認します。
    ///
    /// - Parameter url: 確認するリモートURL。
    /// - Returns: レジュームデータが利用可能な場合は `true`。
    func canResume(for url: URL) -> Bool

    /// URLに対する保存済みレジュームデータを取得します（存在する場合）。
    ///
    /// - Parameter url: 検索するリモートURL。
    /// - Returns: レジュームデータ。保存されていない場合は `nil`。
    func resumeData(for url: URL) -> Data?

    /// アクティブなダウンロードをキャンセルし、レジュームデータを返します。
    ///
    /// - Parameter url: キャンセルするリモートURL。
    /// - Returns: 利用可能なレジュームデータ。なければ `nil`。
    func cancelDownload(for url: URL) async throws -> Data?
}

// MARK: - StubBackgroundDownloadDelegate

/// ネットワークアクセスなしでバックグラウンドダウンロードをシミュレートするデフォルトスタブデリゲート
///
/// カスタムデリゲートが提供されない場合のデフォルトデリゲートとして使用されます。
/// ダウンロードURLの最終パスコンポーネントに基づくシミュレートされたローカルファイルURLを返します。
public struct StubBackgroundDownloadDelegate: BackgroundDownloadDelegate, Sendable {

    public init() {}

    public func startDownload(url: URL, resumeData: Data?) async throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(url.lastPathComponent)
    }

    public func canResume(for url: URL) -> Bool {
        false
    }

    public func resumeData(for url: URL) -> Data? {
        nil
    }

    public func cancelDownload(for url: URL) async throws -> Data? {
        nil
    }
}

// MARK: - BackgroundDownloader

/// レジューム機能付きのバックグラウンドモデルダウンロードを管理するアクター
///
/// `BackgroundDownloader` は大容量モデルファイルのダウンロードに対して、
/// 一時停止・再開・キャンセル操作を提供します。レジュームデータをメモリに保存し、
/// 実際のダウンロード処理を ``BackgroundDownloadDelegate`` に委譲します。
///
/// これはライブラリレベルのアクターです。アプリ側は独自の
/// App Delegate で URLSession バックグラウンドセッションイベントを処理します。
///
/// ## Usage
///
/// ```swift
/// let downloader = BackgroundDownloader()
/// let localURL = try await downloader.download(from: remoteURL)
/// ```
public actor BackgroundDownloader {

    /// バックグラウンドダウンロード用の URLSession 設定識別子。
    public static let sessionIdentifier = "com.llmlocal.background-download"

    /// URLをキーとするアクティブなダウンロードタスク。
    private var activeDownloads: [URL: DownloadState] = [:]

    /// 一時停止・中断されたダウンロードの保存済みレジュームデータ。
    private var resumeDataStore: [URL: Data] = [:]

    /// レジュームデータをディスクに保存するディレクトリ。
    private let storageDirectory: URL

    /// バックグラウンドダウンロードデリゲート（テスト用に注入可能）。
    private let delegate: any BackgroundDownloadDelegate

    /// 新しいバックグラウンドダウンローダーを作成します。
    ///
    /// - Parameters:
    ///   - storageDirectory: レジュームデータをディスクに保存するディレクトリ。
    ///     デフォルトは `~/Library/Application Support/LLMLocal/bg-downloads`。
    ///   - delegate: ダウンロードを実行するオプションのデリゲート。
    ///     `nil` の場合、``StubBackgroundDownloadDelegate`` が使用されます。
    public init(
        storageDirectory: URL? = nil,
        delegate: (any BackgroundDownloadDelegate)? = nil
    ) {
        self.storageDirectory = storageDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("LLMLocal/bg-downloads")
        self.delegate = delegate ?? StubBackgroundDownloadDelegate()
    }

    // MARK: - Public API

    /// URLからのダウンロードを開始または再開します。
    ///
    /// このURLのレジュームデータが存在する場合、ダウンロードの再開に使用されます。
    /// ダウンロード完了時にローカルファイルURLを返します。
    ///
    /// - Parameter url: ダウンロードするリモートURL。
    /// - Returns: ダウンロードが保存されたローカルファイルURL。
    /// - Throws: デリゲートから伝播されたエラー、またはダウンロード失敗時のエラー。
    public func download(from url: URL) async throws -> URL {
        // Check for existing resume data
        let existingResumeData = resumeDataStore[url]

        // Mark as downloading
        activeDownloads[url] = .downloading

        do {
            let localURL = try await delegate.startDownload(
                url: url,
                resumeData: existingResumeData
            )

            // Mark as completed
            activeDownloads[url] = .completed(localURL: localURL)

            // Clean up
            activeDownloads.removeValue(forKey: url)
            resumeDataStore.removeValue(forKey: url)

            return localURL
        } catch {
            // Mark as failed
            activeDownloads[url] = .failed(error: error)
            activeDownloads.removeValue(forKey: url)
            throw error
        }
    }

    /// ダウンロードを一時停止し、レジュームデータを保存します。
    ///
    /// - Parameter url: ダウンロードを一時停止するリモートURL。
    /// - Throws: アクティブなダウンロードが存在しない場合は ``BackgroundDownloadError/notDownloading``。
    public func pause(url: URL) async throws {
        guard activeDownloads[url] != nil else {
            throw BackgroundDownloadError.notDownloading
        }

        // Get resume data from the delegate
        let data = try await delegate.cancelDownload(for: url)

        if let data {
            resumeDataStore[url] = data
            activeDownloads[url] = .paused(resumeData: data)
        } else {
            // Even without data from delegate, mark as paused
            activeDownloads[url] = .paused(resumeData: Data())
            resumeDataStore[url] = Data()
        }
    }

    /// 一時停止したダウンロードを再開します。
    ///
    /// - Parameter url: ダウンロードを再開するリモートURL。
    /// - Returns: ダウンロード完了時のローカルファイルURL。
    /// - Throws: レジュームデータが存在しない場合は ``BackgroundDownloadError/noResumeData``。
    public func resume(url: URL) async throws -> URL {
        guard resumeDataStore[url] != nil else {
            throw BackgroundDownloadError.noResumeData
        }

        // Use the download method which will pick up the resume data
        return try await download(from: url)
    }

    /// ダウンロードをキャンセルし、関連するすべての状態をクリアします。
    ///
    /// このURLのアクティブなダウンロードがない場合、このメソッドは何もしません。
    ///
    /// - Parameter url: キャンセルするリモートURL。
    public func cancel(url: URL) async throws {
        if activeDownloads[url] != nil {
            _ = try? await delegate.cancelDownload(for: url)
        }
        activeDownloads.removeValue(forKey: url)
        resumeDataStore.removeValue(forKey: url)
    }

    /// URLに対してダウンロードが現在アクティブかどうか。
    ///
    /// - Parameter url: 確認するリモートURL。
    /// - Returns: URLがアクティブダウンロード辞書に `.downloading` 状態で存在する場合は `true`。
    public func isDownloading(_ url: URL) -> Bool {
        guard let state = activeDownloads[url] else { return false }
        if case .downloading = state {
            return true
        }
        return false
    }

    /// URLのレジュームデータが存在するかどうか。
    ///
    /// - Parameter url: 確認するリモートURL。
    /// - Returns: このURLのレジュームデータが保存されている場合は `true`。
    public func hasResumeData(for url: URL) -> Bool {
        resumeDataStore[url] != nil
    }

    /// すべてのアクティブなダウンロードURLを返します。
    ///
    /// - Returns: 現在ダウンロード中のURLの配列。
    public func activeDownloadURLs() -> [URL] {
        activeDownloads.compactMap { url, state in
            if case .downloading = state {
                return url
            }
            return nil
        }
    }

    // MARK: - Internal (for testing)

    /// URLをアクティブダウンロード中としてマークします。
    ///
    /// テスト目的で公開されており、一時停止やキャンセルが可能な
    /// 進行中のダウンロードをシミュレートします。
    ///
    /// - Parameter url: ダウンロード中としてマークするURL。
    public func markAsDownloading(_ url: URL) {
        activeDownloads[url] = .downloading
    }
}
