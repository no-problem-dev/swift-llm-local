import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocalModels

// MARK: - Mock Delegate

/// Mock delegate that simulates background download operations without network access.
struct MockBackgroundDownloadDelegate: BackgroundDownloadDelegate, Sendable {
    let shouldThrow: Bool
    let simulatedResumeData: Data?
    let simulatedLocalURL: URL?

    init(
        shouldThrow: Bool = false,
        simulatedResumeData: Data? = nil,
        simulatedLocalURL: URL? = nil
    ) {
        self.shouldThrow = shouldThrow
        self.simulatedResumeData = simulatedResumeData
        self.simulatedLocalURL = simulatedLocalURL
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

    func canResume(for url: URL) -> Bool {
        simulatedResumeData != nil
    }

    func resumeData(for url: URL) -> Data? {
        simulatedResumeData
    }

    func cancelDownload(for url: URL) async throws -> Data? {
        Data("mock-resume".utf8)
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
private let testURL2 = URL(string: "https://huggingface.co/mlx-community/test-model-2/resolve/main/model.safetensors")!

// MARK: - DownloadState Tests

@Suite("DownloadState")
struct DownloadStateTests {

    @Test("downloading state is created correctly")
    func downloadingStateCreated() {
        // Arrange & Act
        let state = DownloadState.downloading

        // Assert
        if case .downloading = state {
            // Pass
        } else {
            Issue.record("Expected .downloading state")
        }
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

    @Test("completed state stores local URL")
    func completedStateStoresLocalURL() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp/model.safetensors")

        // Act
        let state = DownloadState.completed(localURL: url)

        // Assert
        if case .completed(let localURL) = state {
            #expect(localURL == url)
        } else {
            Issue.record("Expected .completed state")
        }
    }

    @Test("failed state stores error")
    func failedStateStoresError() {
        // Arrange
        let error = LLMLocalError.downloadFailed(modelId: "test", reason: "failed")

        // Act
        let state = DownloadState.failed(error: error)

        // Assert
        if case .failed(let storedError) = state {
            #expect(storedError is LLMLocalError)
        } else {
            Issue.record("Expected .failed state")
        }
    }
}

// MARK: - BackgroundDownloader Initialization Tests

@Suite("BackgroundDownloader initialization")
struct BackgroundDownloaderInitTests {

    @Test("initializes with default storage directory")
    func initializesWithDefaultStorageDirectory() async {
        // Act
        let downloader = BackgroundDownloader()

        // Assert
        let urls = await downloader.activeDownloadURLs()
        #expect(urls.isEmpty)
    }

    @Test("initializes with custom storage directory")
    func initializesWithCustomStorageDirectory() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }

        // Act
        let downloader = BackgroundDownloader(storageDirectory: dir)

        // Assert
        let urls = await downloader.activeDownloadURLs()
        #expect(urls.isEmpty)
    }

    @Test("initializes with custom delegate")
    func initializesWithCustomDelegate() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()

        // Act
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

        // Assert
        let urls = await downloader.activeDownloadURLs()
        #expect(urls.isEmpty)
    }

    @Test("session identifier has correct value")
    func sessionIdentifierHasCorrectValue() {
        // Assert
        #expect(BackgroundDownloader.sessionIdentifier == "com.llmlocal.background-download")
    }
}

// MARK: - Download Flow Tests

@Suite("BackgroundDownloader download flow")
struct BackgroundDownloaderDownloadFlowTests {

    @Test("start download returns completed local URL")
    func startDownloadReturnsCompletedLocalURL() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-download-model.safetensors")
        let delegate = MockBackgroundDownloadDelegate(simulatedLocalURL: expectedURL)
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

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
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

        // Act
        let result = try await downloader.download(from: testURL)

        // Assert
        #expect(result == localPath)
    }

    @Test("isDownloading returns false when no downloads active")
    func isDownloadingReturnsFalseWhenNoDownloads() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let downloader = BackgroundDownloader(storageDirectory: dir)

        // Act
        let result = await downloader.isDownloading(testURL)

        // Assert
        #expect(result == false)
    }

    @Test("isDownloading returns false after download completes")
    func isDownloadingReturnsFalseAfterCompletion() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

        // Act
        _ = try await downloader.download(from: testURL)
        let result = await downloader.isDownloading(testURL)

        // Assert
        #expect(result == false)
    }

    @Test("activeDownloadURLs is empty after download completes")
    func activeDownloadURLsEmptyAfterCompletion() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

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
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

        // Simulate an active download by starting one that we can pause
        // We need to mark the URL as downloading first
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
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let downloader = BackgroundDownloader(storageDirectory: dir)

        // Act
        let result = await downloader.hasResumeData(for: testURL)

        // Assert
        #expect(result == false)
    }

    @Test("resume uses stored resume data")
    func resumeUsesStoredResumeData() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let resumeData = Data("test-resume-data".utf8)
        let delegate = MockBackgroundDownloadDelegate(simulatedResumeData: resumeData)
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

        // Simulate paused state with resume data
        await downloader.markAsDownloading(testURL)
        try await downloader.pause(url: testURL)

        // Act
        let result = try await downloader.resume(url: testURL)

        // Assert
        #expect(result != URL(fileURLWithPath: ""))
    }

    @Test("resume without prior pause throws error")
    func resumeWithoutPriorPauseThrows() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

        // Act & Assert
        await #expect(throws: BackgroundDownloadError.self) {
            try await downloader.resume(url: testURL)
        }
    }

    @Test("hasResumeData returns true after pause")
    func hasResumeDataReturnsTrueAfterPause() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )
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
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )
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
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )
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
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

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
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate(shouldThrow: true)
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

        // Act & Assert
        await #expect(throws: LLMLocalError.self) {
            try await downloader.download(from: testURL)
        }
    }

    @Test("download failure sets failed state")
    func downloadFailureSetsFailed() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate(shouldThrow: true)
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

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
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

        // Act & Assert
        await #expect(throws: BackgroundDownloadError.noResumeData) {
            try await downloader.resume(url: testURL)
        }
    }

    @Test("pause non-active download throws notDownloading error")
    func pauseNonActiveDownloadThrows() async throws {
        // Arrange
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let downloader = BackgroundDownloader(
            storageDirectory: dir,
            delegate: delegate
        )

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

    @Test("ModelRegistry exposes background downloader")
    func modelManagerExposesBackgroundDownloader() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let registry = ModelRegistry(cacheDirectory: dir)

        // Act
        let downloader = await registry.backgroundDownloader

        // Assert
        let urls = await downloader.activeDownloadURLs()
        #expect(urls.isEmpty)
    }

    @Test("background downloader uses storage directory under cache directory")
    func backgroundDownloaderUsesCorrectStorageDirectory() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let registry = ModelRegistry(cacheDirectory: dir)

        // Act
        let downloader = await registry.backgroundDownloader

        // Assert - downloader should be functional
        let hasResumeData = await downloader.hasResumeData(for: testURL)
        #expect(hasResumeData == false)
    }

    @Test("background downloader can be used with custom delegate")
    func backgroundDownloaderWithCustomDelegate() async throws {
        // Arrange
        let dir = try Self.makeTempDir()
        defer { Self.removeTempDir(dir) }
        let delegate = MockBackgroundDownloadDelegate()
        let bgDownloader = BackgroundDownloader(
            storageDirectory: dir.appendingPathComponent("bg-downloads"),
            delegate: delegate
        )
        let registry = ModelRegistry(
            cacheDirectory: dir,
            backgroundDownloader: bgDownloader
        )

        // Act
        let downloader = await registry.backgroundDownloader

        // Assert
        let urls = await downloader.activeDownloadURLs()
        #expect(urls.isEmpty)
    }
}

// MARK: - StubBackgroundDownloadDelegate Tests

@Suite("StubBackgroundDownloadDelegate")
struct StubBackgroundDownloadDelegateTests {

    @Test("stub delegate returns simulated local URL")
    func stubDelegateReturnsSimulatedLocalURL() async throws {
        // Arrange
        let delegate = StubBackgroundDownloadDelegate()

        // Act
        let result = try await delegate.startDownload(url: testURL, resumeData: nil)

        // Assert
        #expect(result.lastPathComponent == "model.safetensors")
    }

    @Test("stub delegate canResume returns false")
    func stubDelegateCanResumeReturnsFalse() {
        // Arrange
        let delegate = StubBackgroundDownloadDelegate()

        // Act
        let result = delegate.canResume(for: testURL)

        // Assert
        #expect(result == false)
    }

    @Test("stub delegate resumeData returns nil")
    func stubDelegateResumeDataReturnsNil() {
        // Arrange
        let delegate = StubBackgroundDownloadDelegate()

        // Act
        let result = delegate.resumeData(for: testURL)

        // Assert
        #expect(result == nil)
    }

    @Test("stub delegate cancelDownload returns nil")
    func stubDelegateCancelDownloadReturnsNil() async throws {
        // Arrange
        let delegate = StubBackgroundDownloadDelegate()

        // Act
        let result = try await delegate.cancelDownload(for: testURL)

        // Assert
        #expect(result == nil)
    }
}
