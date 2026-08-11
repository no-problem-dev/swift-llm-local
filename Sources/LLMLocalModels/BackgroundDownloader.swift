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

    /// The transfer was stopped, carrying the resume data when the transport produced any.
    ///
    /// `nil` means the transport could not make the transfer resumable. It is kept distinct from
    /// empty data because the two lead to opposite decisions: a resumable pause continues where it
    /// left off, and a non-resumable one has to start from the first byte — which, for a model, is
    /// gigabytes the caller should be told about rather than discover from the progress bar.
    /// - Parameter resumeData: Bytes the delegate returned when the transfer was cancelled, or
    ///   `nil` when it returned none.
    case paused(resumeData: Data?)
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
    ///   - resumeData: Bytes from a transfer that was cancelled earlier, or `nil` to start from
    ///     the beginning. ``BackgroundDownloader`` passes `nil` when the pause produced no resume
    ///     data; it does not substitute empty data.
    /// - Returns: Location of the finished file on disk.
    func startDownload(url: URL, resumeData: Data?) async throws -> URL

    /// Stops an in-flight transfer and hands back resume data when the transport supports it.
    ///
    /// Called for both pause and cancel. Returning `nil` is taken as "not resumable": the URL is
    /// still marked paused, but no resume data is stored, so ``BackgroundDownloader/resume(url:)``
    /// refuses rather than silently restarting from the first byte.
    ///
    /// Throwing means the transfer was **not** stopped. ``BackgroundDownloader`` keeps its
    /// bookkeeping in that case, so the URL goes on reporting as in flight — which it is.
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
    /// When the delegate returns no resume data, the URL is marked paused but nothing is stored, so
    /// ``hasResumeData(for:)`` answers `false` and ``resume(url:)`` throws
    /// ``BackgroundDownloadError/noResumeData``. That is the honest answer to "can this continue
    /// where it left off": storing empty data instead made every paused URL look resumable and
    /// turned ``resume(url:)`` into a silent restart from byte zero of a multi-gigabyte file. A
    /// caller that wants the restart asks for it with ``download(from:)``.
    ///
    /// What happens to a suspended ``download(from:)`` call is up to the delegate.
    ///
    /// - Parameter url: Remote URL to pause.
    /// - Throws: ``BackgroundDownloadError/notDownloading`` when the URL is not tracked, and
    ///   whatever the delegate throws while cancelling — in which case nothing is marked paused,
    ///   because the transfer was not stopped.
    public func pause(url: URL) async throws {
        guard activeDownloads[url] != nil else {
            throw BackgroundDownloadError.notDownloading
        }

        // Get resume data from the delegate. A throw here means the transfer is still running, so
        // the bookkeeping is left alone and the URL keeps reporting as in flight.
        let data = try await delegate.cancelDownload(for: url)

        resumeDataStore[url] = data
        activeDownloads[url] = .paused(resumeData: data)
    }

    /// Restarts a paused transfer from its stored resume data.
    ///
    /// This is ``download(from:)`` with a precondition: the stored data is picked up there. A pause
    /// the transport could not make resumable stores nothing, so this refuses rather than restarting
    /// from the first byte under the name "resume".
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
    /// first byte. An untracked URL is a no-op.
    ///
    /// The tracking is dropped only once the delegate confirms the transfer stopped. A delegate
    /// that throws leaves everything in place and the error reaches the caller: a transfer that
    /// refused to stop is still moving bytes, and forgetting it would leave ``isDownloading(_:)``
    /// answering `false` about a download that is still running — and no handle left to stop it
    /// with.
    ///
    /// - Parameter url: Remote URL to cancel.
    /// - Throws: Whatever the delegate throws while cancelling.
    public func cancel(url: URL) async throws {
        if activeDownloads[url] != nil {
            _ = try await delegate.cancelDownload(for: url)
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
    /// `true` means ``resume(url:)`` has something to continue from. A pause the transport could
    /// not make resumable answers `false`.
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
