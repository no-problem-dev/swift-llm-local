import Foundation
import LLMLocalClient

// MARK: - DownloadState

/// The stage a tracked download is in.
///
/// ``BackgroundDownloader`` keeps one of these per URL, and only for as long as the URL is being
/// tracked: an entry is removed the moment its transfer finishes or fails, so these two cases are
/// the whole observable lifecycle.
public enum DownloadState: Sendable, Equatable {
    /// A transfer has been handed to the delegate and has not returned yet.
    case downloading

    /// The transfer was stopped and its resume data kept so it can be restarted.
    ///
    /// When the delegate hands back no resume data, an empty `Data` is stored rather than nothing,
    /// so a paused URL always looks resumable even when there is nothing to resume from.
    /// - Parameter resumeData: Bytes the delegate returned when the transfer was cancelled.
    case paused(resumeData: Data)
}

// MARK: - BackgroundDownloadError

/// Errors raised by the download bookkeeping.
public enum BackgroundDownloadError: Error, Sendable, Equatable {
    /// Resume was requested for a URL that has no stored resume data.
    case noResumeData

    /// Pause was requested for a URL that is not being tracked, including one that already
    /// finished.
    case notDownloading
}

// MARK: - BackgroundDownloadDelegate

/// Moves the bytes for a model download.
///
/// ``BackgroundDownloader`` owns only the bookkeeping — which URLs are in flight and which resume
/// data belongs to them — and hands every transfer here. Nothing in this package implements this
/// protocol, so whether a transfer survives app suspension, and whether a `URLSession` background
/// session is involved at all, is decided entirely by the conforming type the app injects.
public protocol BackgroundDownloadDelegate: Sendable {
    /// Starts a transfer, continuing from resume data when it is supplied.
    ///
    /// - Parameters:
    ///   - url: Remote URL to fetch.
    ///   - resumeData: Bytes from a transfer that was cancelled earlier.
    ///     ``BackgroundDownloader`` passes empty data rather than `nil` when a pause produced no
    ///     resume data, so treat empty data as "start from the beginning".
    /// - Returns: Location of the finished file on disk.
    func startDownload(url: URL, resumeData: Data?) async throws -> URL

    /// Stops an in-flight transfer and hands back resume data when the transport supports it.
    ///
    /// Called for both pause and cancel. Returning `nil` is taken as "not resumable": a pause
    /// still marks the URL paused, and the next start receives empty resume data.
    ///
    /// - Parameter url: Remote URL whose transfer should stop.
    /// - Returns: Resume data, or `nil` when the transfer cannot be resumed.
    func cancelDownload(for url: URL) async throws -> Data?
}

// MARK: - BackgroundDownloader

/// Tracks pause, resume, and cancel state for long-running model downloads.
///
/// This actor is bookkeeping only. It records which URLs are in flight, keeps the resume data a
/// pause produced, and forwards every transfer to the ``BackgroundDownloadDelegate`` it was
/// created with. It creates no `URLSession` — background or foreground — and reports no progress;
/// use ``ModelRegistry/downloadWithProgress(_:)`` when byte counts are needed. The delegate is
/// required precisely because this type moves no bytes on its own: without one there would be
/// nothing to track.
///
/// Nothing survives the process. Resume data is held in memory and written nowhere, so a download
/// interrupted by app termination restarts from the first byte, and so does one interrupted by
/// suspension unless the injected delegate arranges otherwise.
///
/// Every query hops onto the actor, so an answer from ``isDownloading(_:)`` or
/// ``hasResumeData(for:)`` can already be stale by the time the caller acts on it.
///
/// ## Usage
///
/// ```swift
/// let downloader = BackgroundDownloader(delegate: myURLSessionDelegate)
/// let localURL = try await downloader.download(from: remoteURL)
/// ```
public actor BackgroundDownloader {

    /// Transfers in flight. Entries are dropped as soon as they finish or fail.
    private var activeDownloads: [URL: DownloadState] = [:]

    /// Resume data from paused transfers. Memory only — it is written nowhere and does not survive
    /// process exit.
    private var resumeDataStore: [URL: Data] = [:]

    /// Performs the transfers.
    private let delegate: any BackgroundDownloadDelegate

    /// Creates a downloader that tracks state in memory and delegates every transfer.
    ///
    /// - Parameter delegate: Performs the transfers. There is no default: this type moves no bytes
    ///   itself, so a downloader without a delegate could only ever report success for work nobody
    ///   did.
    public init(delegate: any BackgroundDownloadDelegate) {
        self.delegate = delegate
    }

    // MARK: - Public API

    /// Starts a transfer, reusing stored resume data for the URL when there is any.
    ///
    /// The URL is marked in flight, handed to the delegate, and cleared from both the in-flight
    /// table and the resume-data table once the delegate returns, so a finished URL is no longer
    /// reported by ``isDownloading(_:)`` or ``hasResumeData(for:)``. On a thrown error the
    /// in-flight entry is cleared too, while resume data kept by an earlier pause is left in place.
    ///
    /// Concurrent starts are not guarded: calling this twice for the same URL runs two delegate
    /// transfers, and the second one owns the bookkeeping.
    ///
    /// - Parameter url: Remote URL to fetch.
    /// - Returns: Location the delegate reported for the finished file.
    /// - Throws: Whatever the delegate throws.
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

            activeDownloads.removeValue(forKey: url)
            resumeDataStore.removeValue(forKey: url)

            return localURL
        } catch {
            activeDownloads.removeValue(forKey: url)
            throw error
        }
    }

    /// Stops the tracked transfer for a URL and keeps whatever resume data comes back.
    ///
    /// When the delegate returns no resume data the URL is still marked paused and empty data is
    /// stored, so ``hasResumeData(for:)`` answers `true` and ``resume(url:)`` succeeds while the
    /// transfer actually restarts from the first byte. What happens to a suspended
    /// ``download(from:)`` call is up to the delegate.
    ///
    /// - Parameter url: Remote URL to pause.
    /// - Throws: ``BackgroundDownloadError/notDownloading`` when the URL is not tracked, and
    ///   whatever the delegate throws while cancelling.
    public func pause(url: URL) async throws {
        guard activeDownloads[url] != nil else {
            throw BackgroundDownloadError.notDownloading
        }

        // Get resume data from the delegate
        let data = try await delegate.cancelDownload(for: url) ?? Data()

        resumeDataStore[url] = data
        activeDownloads[url] = .paused(resumeData: data)
    }

    /// Restarts a paused transfer from its stored resume data.
    ///
    /// This is ``download(from:)`` with a precondition: the stored data is picked up there, so an
    /// empty stored value silently restarts from the beginning.
    ///
    /// - Parameter url: Remote URL to restart.
    /// - Returns: Location the delegate reported for the finished file.
    /// - Throws: ``BackgroundDownloadError/noResumeData`` when nothing is stored for the URL.
    public func resume(url: URL) async throws -> URL {
        guard resumeDataStore[url] != nil else {
            throw BackgroundDownloadError.noResumeData
        }

        // Use the download method which will pick up the resume data
        return try await download(from: url)
    }

    /// Drops all tracking for a URL and tells the delegate to stop.
    ///
    /// Any resume data is discarded, so the next ``download(from:)`` for the URL starts from the
    /// first byte. The delegate's error is swallowed, so this never actually fails despite being
    /// throwing. An untracked URL is a no-op.
    ///
    /// - Parameter url: Remote URL to cancel.
    public func cancel(url: URL) async throws {
        if activeDownloads[url] != nil {
            _ = try? await delegate.cancelDownload(for: url)
        }
        activeDownloads.removeValue(forKey: url)
        resumeDataStore.removeValue(forKey: url)
    }

    /// Reports whether a transfer for the URL is in flight right now.
    ///
    /// A paused URL answers `false` even though its resume data is still held.
    ///
    /// - Parameter url: Remote URL to check.
    /// - Returns: `true` while the delegate call for this URL has not returned.
    public func isDownloading(_ url: URL) -> Bool {
        activeDownloads[url] == .downloading
    }

    /// Reports whether a pause left resume data for the URL.
    ///
    /// Answers `true` after a pause that produced nothing, because empty data is stored in that
    /// case; it is not a promise that the transfer can continue where it left off.
    ///
    /// - Parameter url: Remote URL to check.
    /// - Returns: `true` when an entry exists in the resume-data table.
    public func hasResumeData(for url: URL) -> Bool {
        resumeDataStore[url] != nil
    }

    /// The URLs whose transfers are in flight, excluding paused ones.
    ///
    /// The order is undefined — the entries come from a dictionary.
    public func activeDownloadURLs() -> [URL] {
        activeDownloads.compactMap { url, state in
            state == .downloading ? url : nil
        }
    }

    // MARK: - Internal (for testing)

    /// Marks a URL as in flight without starting a transfer.
    ///
    /// Test seam that lets pause and cancel be exercised with no delegate call running.
    ///
    /// - Parameter url: URL to mark.
    func markAsDownloading(_ url: URL) {
        activeDownloads[url] = .downloading
    }
}
