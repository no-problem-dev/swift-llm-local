import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocalModels

@Suite("DownloadProgress")
struct DownloadProgressTests {

    // MARK: - Test Helpers

    /// Creates a temporary directory for test isolation.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadProgressTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a temporary directory after test use.
    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a sample ModelSpec for testing.
    private static func sampleSpec(
        id: String = "mlx-community/Llama-3.2-1B-Instruct-4bit",
        displayName: String = "Llama 3.2 1B"
    ) -> ModelSpec {
        ModelSpec(
            id: id,
            base: .huggingFace(id: id),
            contextLength: 4096,
            displayName: displayName,
            description: "Test model"
        )
    }

    // MARK: - DownloadProgress Type

    @Suite("type properties")
    struct TypePropertyTests {

        @Test("stores fraction correctly")
        func storesFractionCorrectly() {
            // Arrange & Act
            let progress = DownloadProgress(
                fraction: 0.5,
                completedBytes: 500,
                totalBytes: 1000,
                currentFile: "model.safetensors"
            )

            // Assert
            #expect(progress.fraction == 0.5)
        }

        @Test("stores completedBytes correctly")
        func storesCompletedBytesCorrectly() {
            // Arrange & Act
            let progress = DownloadProgress(
                fraction: 0.25,
                completedBytes: 250_000,
                totalBytes: 1_000_000,
                currentFile: nil
            )

            // Assert
            #expect(progress.completedBytes == 250_000)
        }

        @Test("stores totalBytes correctly")
        func storesTotalBytesCorrectly() {
            // Arrange & Act
            let progress = DownloadProgress(
                fraction: 1.0,
                completedBytes: 2_000_000,
                totalBytes: 2_000_000,
                currentFile: "weights.bin"
            )

            // Assert
            #expect(progress.totalBytes == 2_000_000)
        }

        @Test("stores currentFile as nil when unknown")
        func storesCurrentFileAsNil() {
            // Arrange & Act
            let progress = DownloadProgress(
                fraction: 0.0,
                completedBytes: 0,
                totalBytes: 1000,
                currentFile: nil
            )

            // Assert
            #expect(progress.currentFile == nil)
        }

        @Test("stores currentFile when provided")
        func storesCurrentFileWhenProvided() {
            // Arrange & Act
            let progress = DownloadProgress(
                fraction: 0.3,
                completedBytes: 300,
                totalBytes: 1000,
                currentFile: "config.json"
            )

            // Assert
            #expect(progress.currentFile == "config.json")
        }

        @Test("is Sendable")
        func isSendable() async {
            // Arrange
            let progress = DownloadProgress(
                fraction: 0.5,
                completedBytes: 500,
                totalBytes: 1000,
                currentFile: nil
            )

            // Act - pass across concurrency boundary
            let result: DownloadProgress = await Task {
                progress
            }.value

            // Assert
            #expect(result.fraction == 0.5)
        }
    }

    // MARK: - downloadWithProgress (default delegate / stub)

    @Suite("downloadWithProgress")
    struct DownloadWithProgressTests {

        @Test("yields initial progress with fraction 0.0")
        func yieldsInitialProgress() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let manager = ModelManager(cacheDirectory: dir)
            let spec = DownloadProgressTests.sampleSpec()

            // Act
            let stream = await manager.downloadWithProgress(spec)
            var progressUpdates: [DownloadProgress] = []
            for try await progress in stream {
                progressUpdates.append(progress)
            }

            // Assert
            #expect(progressUpdates.first?.fraction == 0.0)
        }

        @Test("yields completion progress with fraction 1.0")
        func yieldsCompletionProgress() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let manager = ModelManager(cacheDirectory: dir)
            let spec = DownloadProgressTests.sampleSpec()

            // Act
            let stream = await manager.downloadWithProgress(spec)
            var progressUpdates: [DownloadProgress] = []
            for try await progress in stream {
                progressUpdates.append(progress)
            }

            // Assert
            #expect(progressUpdates.last?.fraction == 1.0)
        }

        @Test("transitions from 0.0 to 1.0")
        func transitionsFromZeroToOne() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let manager = ModelManager(cacheDirectory: dir)
            let spec = DownloadProgressTests.sampleSpec()

            // Act
            let stream = await manager.downloadWithProgress(spec)
            var progressUpdates: [DownloadProgress] = []
            for try await progress in stream {
                progressUpdates.append(progress)
            }

            // Assert
            #expect(progressUpdates.count >= 2)
            #expect(progressUpdates.first?.fraction == 0.0)
            #expect(progressUpdates.last?.fraction == 1.0)
        }

        @Test("registers model in cache after completion")
        func registersModelInCacheAfterCompletion() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let manager = ModelManager(cacheDirectory: dir)
            let spec = DownloadProgressTests.sampleSpec()

            // Act - consume the entire stream
            let stream = await manager.downloadWithProgress(spec)
            for try await _ in stream {}

            // Assert
            let isCached = await manager.isCached(spec)
            #expect(isCached == true)
        }
    }

    // MARK: - downloadWithProgress (mock delegate)

    @Suite("downloadWithProgress with mock delegate")
    struct MockDelegateTests {

        /// A mock delegate that simulates multi-step progress updates.
        struct MultiStepDelegate: DownloadProgressDelegate {
            let steps: [Double]
            let totalSize: Int64

            func download(
                _ spec: ModelSpec,
                progressHandler: @Sendable (DownloadProgress) -> Void
            ) async throws -> Int64 {
                let total = totalSize
                for step in steps {
                    let completed = Int64(Double(total) * step)
                    progressHandler(DownloadProgress(
                        fraction: step,
                        completedBytes: completed,
                        totalBytes: total,
                        currentFile: "model.safetensors"
                    ))
                }
                return total
            }
        }

        /// A mock delegate that throws an error during download.
        struct ErrorDelegate: DownloadProgressDelegate {
            let error: any Error

            func download(
                _ spec: ModelSpec,
                progressHandler: @Sendable (DownloadProgress) -> Void
            ) async throws -> Int64 {
                progressHandler(DownloadProgress(
                    fraction: 0.0,
                    completedBytes: 0,
                    totalBytes: 1000,
                    currentFile: nil
                ))
                throw error
            }
        }

        @Test("receives multiple progress updates from delegate")
        func receivesMultipleProgressUpdates() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let delegate = MultiStepDelegate(
                steps: [0.25, 0.5, 0.75],
                totalSize: 4_000_000
            )
            let manager = ModelManager(cacheDirectory: dir, downloadDelegate: delegate)
            let spec = DownloadProgressTests.sampleSpec()

            // Act
            let stream = await manager.downloadWithProgress(spec)
            var progressUpdates: [DownloadProgress] = []
            for try await progress in stream {
                progressUpdates.append(progress)
            }

            // Assert - should have: initial(0.0), delegate(0.25, 0.5, 0.75), completion(1.0)
            #expect(progressUpdates.count == 5)
            #expect(progressUpdates[0].fraction == 0.0)
            #expect(progressUpdates[1].fraction == 0.25)
            #expect(progressUpdates[2].fraction == 0.5)
            #expect(progressUpdates[3].fraction == 0.75)
            #expect(progressUpdates[4].fraction == 1.0)
        }

        @Test("delegate progress includes currentFile")
        func delegateProgressIncludesCurrentFile() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let delegate = MultiStepDelegate(
                steps: [0.5],
                totalSize: 1_000_000
            )
            let manager = ModelManager(cacheDirectory: dir, downloadDelegate: delegate)
            let spec = DownloadProgressTests.sampleSpec()

            // Act
            let stream = await manager.downloadWithProgress(spec)
            var progressUpdates: [DownloadProgress] = []
            for try await progress in stream {
                progressUpdates.append(progress)
            }

            // Assert
            #expect(progressUpdates[1].currentFile == "model.safetensors")
        }

        @Test("registers model with size from delegate after completion")
        func registersModelWithSizeFromDelegate() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let delegate = MultiStepDelegate(
                steps: [0.5],
                totalSize: 2_500_000
            )
            let manager = ModelManager(cacheDirectory: dir, downloadDelegate: delegate)
            let spec = DownloadProgressTests.sampleSpec()

            // Act
            let stream = await manager.downloadWithProgress(spec)
            for try await _ in stream {}

            // Assert
            let models = await manager.cachedModels()
            #expect(models.count == 1)
            #expect(models[0].sizeInBytes == 2_500_000)
        }

        @Test("handles delegate throwing error")
        func handlesDelegateThrowingError() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let delegate = ErrorDelegate(
                error: LLMLocalError.downloadFailed(
                    modelId: "test",
                    reason: "network error"
                )
            )
            let manager = ModelManager(cacheDirectory: dir, downloadDelegate: delegate)
            let spec = DownloadProgressTests.sampleSpec()

            // Act & Assert
            let stream = await manager.downloadWithProgress(spec)
            var receivedError: (any Error)?
            do {
                for try await _ in stream {}
            } catch {
                receivedError = error
            }

            #expect(receivedError != nil)
            if let llmError = receivedError as? LLMLocalError {
                #expect(llmError == .downloadFailed(modelId: "test", reason: "network error"))
            } else {
                Issue.record("Expected LLMLocalError but got \(type(of: receivedError!))")
            }
        }

        @Test("does not register model when delegate throws")
        func doesNotRegisterModelWhenDelegateThrows() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let delegate = ErrorDelegate(
                error: LLMLocalError.downloadFailed(
                    modelId: "test",
                    reason: "network error"
                )
            )
            let manager = ModelManager(cacheDirectory: dir, downloadDelegate: delegate)
            let spec = DownloadProgressTests.sampleSpec()

            // Act - consume stream, ignoring error
            let stream = await manager.downloadWithProgress(spec)
            do {
                for try await _ in stream {}
            } catch {
                // Expected error
            }

            // Assert - model should NOT be cached
            let isCached = await manager.isCached(spec)
            #expect(isCached == false)
        }
    }

    // MARK: - Cancellation

    @Suite("cancellation")
    struct CancellationTests {

        /// A mock delegate that waits for cancellation.
        struct SlowDelegate: DownloadProgressDelegate {
            func download(
                _ spec: ModelSpec,
                progressHandler: @Sendable (DownloadProgress) -> Void
            ) async throws -> Int64 {
                progressHandler(DownloadProgress(
                    fraction: 0.1,
                    completedBytes: 100,
                    totalBytes: 1000,
                    currentFile: nil
                ))
                // Simulate a long download that respects cancellation
                try await Task.sleep(for: .seconds(10))
                return 1000
            }
        }

        @Test("handles cancellation")
        func handlesCancellation() async throws {
            // Arrange
            let dir = try DownloadProgressTests.makeTempDir()
            defer { DownloadProgressTests.removeTempDir(dir) }
            let delegate = SlowDelegate()
            let manager = ModelManager(cacheDirectory: dir, downloadDelegate: delegate)
            let spec = DownloadProgressTests.sampleSpec()

            // Act
            let stream = await manager.downloadWithProgress(spec)
            let task = Task {
                var updates: [DownloadProgress] = []
                do {
                    for try await progress in stream {
                        updates.append(progress)
                    }
                } catch is CancellationError {
                    // Expected
                } catch {
                    // Other errors from cancellation are also acceptable
                }
                return updates
            }

            // Give the task a moment to start
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()

            let updates = await task.value

            // Assert - should have received at least the initial progress
            #expect(updates.count >= 1)
            #expect(updates[0].fraction == 0.0)

            // Model should NOT be registered since download was cancelled
            let isCached = await manager.isCached(spec)
            #expect(isCached == false)
        }
    }
}
