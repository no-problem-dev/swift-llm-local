import Foundation
import LLMLocalClient

// MARK: - DownloadState

/// Internal state for tracking a background download.
public enum DownloadState: Sendable {
    /// The download is actively in progress.
    case downloading

    /// The download has been paused with resume data stored.
    case paused(resumeData: Data)

    /// The download completed successfully.
    case completed(localURL: URL)

    /// The download failed with an error.
    case failed(error: any Error)
}

// MARK: - BackgroundDownloadError

/// Errors specific to background download operations.
public enum BackgroundDownloadError: Error, Sendable, Equatable {
    /// No resume data is available for the requested URL.
    case noResumeData

    /// The requested URL is not currently downloading.
    case notDownloading

    /// Resume data persistence failed.
    case resumeDataPersistenceFailed(reason: String)
}

// MARK: - BackgroundDownloadDelegate

/// Protocol for background download operations.
///
/// Enables dependency injection for testing. Implementations provide the
/// actual URLSession background download behavior or a test stub.
public protocol BackgroundDownloadDelegate: Sendable {
    /// Starts or resumes a background download.
    ///
    /// - Parameters:
    ///   - url: The remote URL to download from.
    ///   - resumeData: Optional resume data from a previously paused download.
    /// - Returns: The local file URL where the download was saved.
    /// - Throws: Any error that occurs during the download.
    func startDownload(url: URL, resumeData: Data?) async throws -> URL

    /// Checks if a download can be resumed for the given URL.
    ///
    /// - Parameter url: The remote URL to check.
    /// - Returns: `true` if resume data is available.
    func canResume(for url: URL) -> Bool

    /// Gets stored resume data for a URL, if available.
    ///
    /// - Parameter url: The remote URL to look up.
    /// - Returns: The resume data, or `nil` if none is stored.
    func resumeData(for url: URL) -> Data?

    /// Cancels an active download and returns any resume data.
    ///
    /// - Parameter url: The remote URL to cancel.
    /// - Returns: Resume data if available, or `nil`.
    func cancelDownload(for url: URL) async throws -> Data?
}

// MARK: - StubBackgroundDownloadDelegate

/// Default stub delegate that simulates background downloads without network access.
///
/// Used as the default delegate when no custom delegate is provided.
/// Returns a simulated local file URL based on the download URL's last path component.
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

/// Manages background model downloads with resume capability.
///
/// `BackgroundDownloader` provides pause, resume, and cancel operations for
/// large model file downloads. It stores resume data in memory and delegates
/// the actual download work to a ``BackgroundDownloadDelegate``.
///
/// This is a library-level actor. The consumer app integrates with its own
/// app delegate for URLSession background session event handling.
///
/// ## Usage
///
/// ```swift
/// let downloader = BackgroundDownloader()
/// let localURL = try await downloader.download(from: remoteURL)
/// ```
public actor BackgroundDownloader {

    /// The URLSession configuration identifier for background downloads.
    public static let sessionIdentifier = "com.llmlocal.background-download"

    /// Active download tasks keyed by URL.
    private var activeDownloads: [URL: DownloadState] = [:]

    /// Stored resume data for paused/interrupted downloads.
    private var resumeDataStore: [URL: Data] = [:]

    /// Directory for storing resume data on disk.
    private let storageDirectory: URL

    /// The background download delegate (injectable for testing).
    private let delegate: any BackgroundDownloadDelegate

    /// Creates a new background downloader.
    ///
    /// - Parameters:
    ///   - storageDirectory: Directory for storing resume data on disk.
    ///     Defaults to `~/Library/Application Support/LLMLocal/bg-downloads`.
    ///   - delegate: An optional delegate for performing downloads.
    ///     When `nil`, a ``StubBackgroundDownloadDelegate`` is used.
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

    /// Starts or resumes downloading from the URL.
    ///
    /// If resume data exists for this URL, it will be used to resume the download.
    /// Returns the local file URL when the download completes.
    ///
    /// - Parameter url: The remote URL to download.
    /// - Returns: The local file URL where the download was saved.
    /// - Throws: Any error propagated from the delegate or if the download fails.
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

    /// Pauses a download and stores resume data.
    ///
    /// - Parameter url: The remote URL whose download should be paused.
    /// - Throws: ``BackgroundDownloadError/notDownloading`` if no active download exists.
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

    /// Resumes a paused download.
    ///
    /// - Parameter url: The remote URL to resume downloading.
    /// - Returns: The local file URL when the download completes.
    /// - Throws: ``BackgroundDownloadError/noResumeData`` if no resume data exists.
    public func resume(url: URL) async throws -> URL {
        guard resumeDataStore[url] != nil else {
            throw BackgroundDownloadError.noResumeData
        }

        // Use the download method which will pick up the resume data
        return try await download(from: url)
    }

    /// Cancels a download and clears all associated state.
    ///
    /// If no download is active for the URL, this method is a no-op.
    ///
    /// - Parameter url: The remote URL to cancel.
    public func cancel(url: URL) async throws {
        if activeDownloads[url] != nil {
            _ = try? await delegate.cancelDownload(for: url)
        }
        activeDownloads.removeValue(forKey: url)
        resumeDataStore.removeValue(forKey: url)
    }

    /// Whether a download is currently active for the URL.
    ///
    /// - Parameter url: The remote URL to check.
    /// - Returns: `true` if the URL is in the active downloads dictionary with a `.downloading` state.
    public func isDownloading(_ url: URL) -> Bool {
        guard let state = activeDownloads[url] else { return false }
        if case .downloading = state {
            return true
        }
        return false
    }

    /// Whether resume data exists for the URL.
    ///
    /// - Parameter url: The remote URL to check.
    /// - Returns: `true` if resume data is stored for this URL.
    public func hasResumeData(for url: URL) -> Bool {
        resumeDataStore[url] != nil
    }

    /// Returns all active download URLs.
    ///
    /// - Returns: An array of URLs that are currently being downloaded.
    public func activeDownloadURLs() -> [URL] {
        activeDownloads.compactMap { url, state in
            if case .downloading = state {
                return url
            }
            return nil
        }
    }

    // MARK: - Internal (for testing)

    /// Marks a URL as actively downloading.
    ///
    /// This is exposed for testing purposes to simulate an in-progress download
    /// that can then be paused or cancelled.
    ///
    /// - Parameter url: The URL to mark as downloading.
    public func markAsDownloading(_ url: URL) {
        activeDownloads[url] = .downloading
    }
}
