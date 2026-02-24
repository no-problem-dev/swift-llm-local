import Foundation
import Testing
import LLMLocalClient
@testable import LLMLocal
@testable import LLMLocalMLX

// MARK: - Test Helpers

/// A mock memory provider for LLMLocalService integration tests.
private struct MockMemoryProvider: MemoryProvider, Sendable {
    let totalMemory: UInt64
    let availableMemory: UInt64

    func totalMemoryBytes() -> UInt64 { totalMemory }
    func availableMemoryBytes() -> UInt64 { availableMemory }
}

// MARK: - LLMLocalService Memory Integration Tests

@Suite("LLMLocalService memory monitoring integration")
struct LLMLocalServiceMemoryTests {

    /// Creates a temporary directory for test isolation.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMLocalServiceMemoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a temporary directory after test use.
    private static func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("recommendedContextLength returns value when monitor is configured")
    func recommendedContextLengthWithMonitor() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // Act
        let contextLength = await service.recommendedContextLength()

        // Assert
        #expect(contextLength == 2048)
    }

    @Test("recommendedContextLength returns nil when no monitor is configured")
    func recommendedContextLengthWithoutMonitor() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        // Act
        let contextLength = await service.recommendedContextLength()

        // Assert
        #expect(contextLength == nil)
    }

    @Test("recommendedContextLength returns 4096 for high memory device")
    func recommendedContextLengthHighMemory() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let provider = MockMemoryProvider(
            totalMemory: 16 * 1024 * 1024 * 1024,
            availableMemory: 10 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // Act
        let contextLength = await service.recommendedContextLength()

        // Assert
        #expect(contextLength == 4096)
    }

    @Test("memory warning triggers model unload via service")
    func memoryWarningTriggersModelUnload() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 2 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // Load a model first
        let spec = ModelSpec(
            id: "test-model",
            base: .huggingFace(id: "mlx-community/test-model"),
            contextLength: 4096,
            displayName: "Test Model",
            description: "Test model",
            estimatedMemoryBytes: 4_500_000_000
        )
        try await backend.loadModel(spec)
        let isLoadedBefore = await backend.isLoaded
        #expect(isLoadedBefore == true)

        // Start monitoring
        await service.startMemoryMonitoring()

        // Give the notification listener time to set up
        try await Task.sleep(for: .milliseconds(50))

        // Act: post memory warning notification
        NotificationCenter.default.post(
            name: MemoryMonitor.memoryWarningNotificationName,
            object: nil
        )

        // Wait for async handler to execute
        try await Task.sleep(for: .milliseconds(200))

        // Assert: model should be unloaded
        let unloadCalled = await backend.unloadCalled
        #expect(unloadCalled == true)

        // Cleanup
        await service.stopMemoryMonitoring()
    }

    @Test("stopMemoryMonitoring stops the monitoring")
    func stopMemoryMonitoringStopsMonitoring() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // Start and then stop monitoring
        await service.startMemoryMonitoring()
        await service.stopMemoryMonitoring()

        // Assert: monitor should no longer be monitoring
        let isMonitoring = await monitor.isCurrentlyMonitoring
        #expect(isMonitoring == false)
    }

    @Test("startMemoryMonitoring does nothing when no monitor configured")
    func startMemoryMonitoringWithoutMonitor() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        // Act: should not crash
        await service.startMemoryMonitoring()
        await service.stopMemoryMonitoring()

        // Assert: no-op completed without crash
        let contextLength = await service.recommendedContextLength()
        #expect(contextLength == nil)
    }

    @Test("existing init without memoryMonitor still works")
    func existingInitStillWorks() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)

        // Act: the old init signature should still work
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        // Assert
        let contextLength = await service.recommendedContextLength()
        #expect(contextLength == nil)
    }

    @Test("totalMemory returns value when monitor provided")
    func totalMemoryReturnsValueWhenMonitorProvided() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let provider = MockMemoryProvider(
            totalMemory: 16 * 1024 * 1024 * 1024,
            availableMemory: 8 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // Act
        let total = await service.totalMemory()

        // Assert
        let expected: UInt64 = 16 * 1024 * 1024 * 1024
        #expect(total == expected)
    }

    @Test("isModelCompatible returns true for small model")
    func isModelCompatibleReturnsTrueForSmallModel() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let provider = MockMemoryProvider(
            totalMemory: 16 * 1024 * 1024 * 1024,
            availableMemory: 8 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // A small model (4.5 GB) on a 16 GB device should be compatible
        let spec = ModelSpec(
            id: "small-model",
            base: .huggingFace(id: "mlx-community/small-model"),
            contextLength: 4096,
            displayName: "Small Model",
            description: "Small test model",
            estimatedMemoryBytes: 4_500_000_000
        )

        // Act
        let compatible = await service.isModelCompatible(spec)

        // Assert
        #expect(compatible == true)
    }

    @Test("isModelCompatible returns false for oversized model")
    func isModelCompatibleReturnsFalseForOversizedModel() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // A large model (15 GB) on an 8 GB device should not be compatible
        let spec = ModelSpec(
            id: "large-model",
            base: .huggingFace(id: "mlx-community/large-model"),
            contextLength: 4096,
            displayName: "Large Model",
            description: "Large test model",
            estimatedMemoryBytes: 15_000_000_000
        )

        // Act
        let compatible = await service.isModelCompatible(spec)

        // Assert
        #expect(compatible == false)
    }

    @Test("maxAllowedModelMemory returns 80 percent of total")
    func maxAllowedModelMemoryReturns80PercentOfTotal() async throws {
        // Arrange
        let dir = try LLMLocalServiceMemoryTests.makeTempDir()
        defer { LLMLocalServiceMemoryTests.removeTempDir(dir) }

        let totalMem: UInt64 = 16 * 1024 * 1024 * 1024
        let provider = MockMemoryProvider(
            totalMemory: totalMem,
            availableMemory: 8 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        let backend = MockBackend()
        let modelManager = ModelManager(cacheDirectory: dir)
        let service = LLMLocalService(
            backend: backend,
            modelManager: modelManager,
            memoryMonitor: monitor
        )

        // Act
        let maxMemory = await service.maxAllowedModelMemory()

        // Assert
        let expected = UInt64(Double(totalMem) * 0.8)
        #expect(maxMemory == expected)
    }
}
