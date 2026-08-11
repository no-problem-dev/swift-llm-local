import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocalModels

// MARK: - Mock Delegate

/// Mock delegate that simulates background download operations without network access.
struct MockBackgroundDownloadDelegate: BackgroundDownloadDelegate, Sendable {
    let shouldThrow: Bool
    let simulatedLocalURL: URL?

    /// What `cancelDownload(for:)` hands back. `nil` models a transport that cannot resume.
    let cancelResumeData: Data?

    init(
        shouldThrow: Bool = false,
        simulatedLocalURL: URL? = nil,
        cancelResumeData: Data? = Data("mock-resume".utf8)
    ) {
        self.shouldThrow = shouldThrow
        self.simulatedLocalURL = simulatedLocalURL
        self.cancelResumeData = cancelResumeData
    }

    func startDownload(url: URL, resumeData: Data?) async throws -> URL {
        if shouldThrow {
            throw LLMLocalError.downloadFailed(
                modelId: url.absoluteString,
                reason: "mock error"
            )
        }
        return simulatedLocalURL
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("mock-download-\(url.lastPathComponent)")
    }

    func cancelDownload(for url: URL) async throws -> Data? {
        cancelResumeData
    }
}

/// Records the resume data each `startDownload` call received, so the resume path can be asserted.
actor RecordingBackgroundDownloadDelegate: BackgroundDownloadDelegate {
    private(set) var receivedResumeData: [Data?] = []
    private let cancelResumeData: Data?

    init(cancelResumeData: Data? = Data("recorded-resume".utf8)) {
        self.cancelResumeData = cancelResumeData
    }

    func startDownload(url: URL, resumeData: Data?) async throws -> URL {
        receivedResumeData.append(resumeData)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("recorded-\(url.lastPathComponent)")
    }

    func cancelDownload(for url: URL) async throws -> Data? {
        cancelResumeData
    }
}

// MARK: - Test Helpers

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("BackgroundDownloaderTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func removeTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private let testURL = URL(string: "https://huggingface.co/mlx-community/test-model/resolve/main/model.safetensors")!

// MARK: - DownloadState Tests

@Suite("DownloadState")
struct DownloadStateTests {

    @Test("downloading state is created correctly")
    func downloadingStateCreated() {
        // Arrange & Act
        let state = DownloadState.downloading

        // Assert
        #expect(state == .downloading)
    }

    @Test("paused state stores resume data")
    func pausedStateStoresResumeData() {
        // Arrange
        let data = Data("resume-data".utf8)

        // Act
        let state = DownloadState.paused(resumeData: data)

        // Assert
        if case .paused(let resumeData) = state {
            #expect(resumeData == data)
        } else {
            Issue.record("Expected .paused state")
        }
    }
}

// MARK: - BackgroundDownloader Initialization Tests

@Suite("BackgroundDownloader initialization")
struct BackgroundDownloaderInitTests {

    @Test("initializes with an injected delegate and tracks nothing")
    func initializesWithCustomDelegate() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()

        // Act
        let downloader = BackgroundDownloader(delegate: delegate)

        // Assert
        let urls = await downloader.activeDownloadURLs()
        #expect(urls.isEmpty)
    }
}

// MARK: - Download Flow Tests

@Suite("BackgroundDownloader download flow")
struct BackgroundDownloaderDownloadFlowTests {

    @Test("start download returns completed local URL")
    func startDownloadReturnsCompletedLocalURL() async throws {
        // Arrange
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-download-model.safetensors")
        let delegate = MockBackgroundDownloadDelegate(simulatedLocalURL: expectedURL)
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act
        let result = try await downloader.download(from: testURL)

        // Assert
        #expect(result == expectedURL)
    }

    @Test("download returns correct local URL from delegate")
    func downloadReturnsCorrectLocalURL() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let localPath = dir.appendingPathComponent("downloaded-model.bin")
        let delegate = MockBackgroundDownloadDelegate(simulatedLocalURL: localPath)
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act
        let result = try await downloader.download(from: testURL)

        // Assert
        #expect(result == localPath)
    }

    @Test("isDownloading returns false when no downloads active")
    func isDownloadingReturnsFalseWhenNoDownloads() async throws {
        // Arrange
        let downloader = BackgroundDownloader(delegate: MockBackgroundDownloadDelegate())

        // Act
        let result = await downloader.isDownloading(testURL)

        // Assert
        #expect(result == false)
    }

    @Test("isDownloading returns false after download completes")
    func isDownloadingReturnsFalseAfterCompletion() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act
        _ = try await downloader.download(from: testURL)
        let result = await downloader.isDownloading(testURL)

        // Assert
        #expect(result == false)
    }

    @Test("activeDownloadURLs is empty after download completes")
    func activeDownloadURLsEmptyAfterCompletion() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act
        _ = try await downloader.download(from: testURL)
        let urls = await downloader.activeDownloadURLs()

        // Assert
        #expect(urls.isEmpty)
    }
}

// MARK: - Pause/Resume Flow Tests

@Suite("BackgroundDownloader pause/resume flow")
struct BackgroundDownloaderPauseResumeFlowTests {

    @Test("pause stores resume data via delegate")
    func pauseStoresResumeData() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)

        // Simulate an active download by marking the URL as downloading
        await downloader.markAsDownloading(testURL)

        // Act
        try await downloader.pause(url: testURL)

        // Assert
        let hasData = await downloader.hasResumeData(for: testURL)
        #expect(hasData == true)
    }

    @Test("hasResumeData returns false when no resume data exists")
    func hasResumeDataReturnsFalseWhenNoData() async throws {
        // Arrange
        let downloader = BackgroundDownloader(delegate: MockBackgroundDownloadDelegate())

        // Act
        let result = await downloader.hasResumeData(for: testURL)

        // Assert
        #expect(result == false)
    }

    @Test("resume hands the stored resume data back to the delegate")
    func resumeUsesStoredResumeData() async throws {
        // Arrange
        let resumeData = Data("test-resume-data".utf8)
        let delegate = RecordingBackgroundDownloadDelegate(cancelResumeData: resumeData)
        let downloader = BackgroundDownloader(delegate: delegate)

        // Simulate paused state with resume data
        await downloader.markAsDownloading(testURL)
        try await downloader.pause(url: testURL)

        // Act
        _ = try await downloader.resume(url: testURL)

        // Assert
        let received = await delegate.receivedResumeData
        #expect(received == [resumeData])
    }

    /// A pause the transport could not make resumable still marks the URL paused, and the restart
    /// receives empty data rather than nothing.
    @Test("pause with no delegate resume data stores empty data")
    func pauseWithoutDelegateDataStoresEmpty() async throws {
        // Arrange
        let delegate = RecordingBackgroundDownloadDelegate(cancelResumeData: nil)
        let downloader = BackgroundDownloader(delegate: delegate)
        await downloader.markAsDownloading(testURL)

        // Act
        try await downloader.pause(url: testURL)
        _ = try await downloader.resume(url: testURL)

        // Assert
        let hasData = await downloader.hasResumeData(for: testURL)
        #expect(hasData == false) // Cleared once the transfer finished.
        let received = await delegate.receivedResumeData
        #expect(received == [Data()])
    }

    @Test("resume without prior pause throws error")
    func resumeWithoutPriorPauseThrows() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act & Assert
        await #expect(throws: BackgroundDownloadError.self) {
            try await downloader.resume(url: testURL)
        }
    }

    @Test("hasResumeData returns true after pause")
    func hasResumeDataReturnsTrueAfterPause() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)
        await downloader.markAsDownloading(testURL)

        // Act
        try await downloader.pause(url: testURL)
        let result = await downloader.hasResumeData(for: testURL)

        // Assert
        #expect(result == true)
    }
}

// MARK: - Cancel Flow Tests

@Suite("BackgroundDownloader cancel flow")
struct BackgroundDownloaderCancelFlowTests {

    @Test("cancel removes from active downloads")
    func cancelRemovesFromActiveDownloads() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)
        await downloader.markAsDownloading(testURL)

        // Act
        try await downloader.cancel(url: testURL)

        // Assert
        let isDownloading = await downloader.isDownloading(testURL)
        #expect(isDownloading == false)
    }

    @Test("cancel clears resume data")
    func cancelClearsResumeData() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)
        await downloader.markAsDownloading(testURL)
        try await downloader.pause(url: testURL)

        // Pre-condition: resume data exists
        let hasDataBefore = await downloader.hasResumeData(for: testURL)
        #expect(hasDataBefore == true)

        // Act
        try await downloader.cancel(url: testURL)

        // Assert
        let hasDataAfter = await downloader.hasResumeData(for: testURL)
        #expect(hasDataAfter == false)
    }

    @Test("cancel non-existent download is no-op")
    func cancelNonExistentDownloadIsNoOp() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act & Assert - should not throw
        try await downloader.cancel(url: testURL)

        let isDownloading = await downloader.isDownloading(testURL)
        #expect(isDownloading == false)
    }
}

// MARK: - Error Handling Tests

@Suite("BackgroundDownloader error handling")
struct BackgroundDownloaderErrorHandlingTests {

    @Test("download failure propagates error from delegate")
    func downloadFailurePropagatesError() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate(shouldThrow: true)
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act & Assert
        await #expect(throws: LLMLocalError.self) {
            try await downloader.download(from: testURL)
        }
    }

    @Test("download failure clears the in-flight entry")
    func downloadFailureClearsInFlightEntry() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate(shouldThrow: true)
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act
        do {
            _ = try await downloader.download(from: testURL)
        } catch {
            // Expected
        }

        // Assert - download should not be active
        let isDownloading = await downloader.isDownloading(testURL)
        #expect(isDownloading == false)
    }

    @Test("resume with no resume data throws noResumeData error")
    func resumeWithNoResumeDataThrows() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act & Assert
        await #expect(throws: BackgroundDownloadError.noResumeData) {
            try await downloader.resume(url: testURL)
        }
    }

    @Test("pause non-active download throws notDownloading error")
    func pauseNonActiveDownloadThrows() async throws {
        // Arrange
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(delegate: delegate)

        // Act & Assert
        await #expect(throws: BackgroundDownloadError.notDownloading) {
            try await downloader.pause(url: testURL)
        }
    }
}

// MARK: - ModelRegistry Integration Tests

@Suite("ModelRegistry background downloader integration")
struct ModelRegistryBackgroundDownloaderTests {

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelRegistryBGTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// The registry has no delegate that moves bytes, so it must not conjure a downloader that
    /// would report instant success for transfers nobody performed.
    @Test("registry hands back no downloader when none was injected")
    func registryWithoutInjectedDownloaderHasNone() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let registry = ModelRegistry(cacheDirectory: dir)

        // Act
        let downloader = await registry.backgroundDownloader

        // Assert
        #expect(downloader == nil)
    }

    @Test("registry exposes the downloader it was given")
    func registryExposesInjectedDownloader() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let bgDownloader = BackgroundDownloader(delegate: delegate)
        let registry = ModelRegistry(
            cacheDirectory: dir,
            backgroundDownloader: bgDownloader
        )

        // Act
        let downloader = await registry.backgroundDownloader

        // Assert
        let urls = await downloader?.activeDownloadURLs()
        #expect(urls == [])
    }
}
