import Foundation
import Testing
@testable import LLMLocalMLX

// MARK: - Mock Memory Provider

struct MockMemoryProvider: MemoryProvider, Sendable {
    let totalMemory: UInt64
    let availableMemory: UInt64

    func totalMemoryBytes() -> UInt64 { totalMemory }
    func availableMemoryBytes() -> UInt64 { availableMemory }
}

// MARK: - Thread-safe atomic helper for tests

/// A simple atomic boolean wrapper for test verification across async boundaries.
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ initialValue: Bool) {
        self.value = initialValue
    }

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - Device Memory Tier Tests

@Suite("MemoryMonitor deviceMemoryTier")
struct MemoryMonitorDeviceMemoryTierTests {

    @Test("returns .standard for 8GB device")
    func returnsStandardFor8GB() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        let tier = await monitor.deviceMemoryTier()

        // Assert
        #expect(tier == .standard)
    }

    @Test("returns .high for 12GB device")
    func returnsHighFor12GB() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 12 * 1024 * 1024 * 1024,
            availableMemory: 8 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        let tier = await monitor.deviceMemoryTier()

        // Assert
        #expect(tier == .high)
    }

    @Test("returns .high for 16GB device")
    func returnsHighFor16GB() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 16 * 1024 * 1024 * 1024,
            availableMemory: 10 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        let tier = await monitor.deviceMemoryTier()

        // Assert
        #expect(tier == .high)
    }

    @Test("returns .standard for 6GB device")
    func returnsStandardFor6GB() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 6 * 1024 * 1024 * 1024,
            availableMemory: 3 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        let tier = await monitor.deviceMemoryTier()

        // Assert
        #expect(tier == .standard)
    }

    @Test("returns .standard for boundary value just below 12GB")
    func returnsStandardForJustBelow12GB() async {
        // Arrange: 12GB - 1 byte
        let provider = MockMemoryProvider(
            totalMemory: 12 * 1024 * 1024 * 1024 - 1,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        let tier = await monitor.deviceMemoryTier()

        // Assert
        #expect(tier == .standard)
    }
}

// MARK: - Recommended Context Length Tests

@Suite("MemoryMonitor recommendedContextLength")
struct MemoryMonitorRecommendedContextLengthTests {

    @Test("returns 2048 for 8GB device")
    func returns2048For8GBDevice() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        let contextLength = await monitor.recommendedContextLength()

        // Assert
        #expect(contextLength == 2048)
    }

    @Test("returns 4096 for 12GB device")
    func returns4096For12GBDevice() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 12 * 1024 * 1024 * 1024,
            availableMemory: 8 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        let contextLength = await monitor.recommendedContextLength()

        // Assert
        #expect(contextLength == 4096)
    }
}

// MARK: - Available Memory Tests

@Suite("MemoryMonitor availableMemory")
struct MemoryMonitorAvailableMemoryTests {

    @Test("returns the provider's available memory value")
    func returnsProviderValue() async {
        // Arrange
        let expectedAvailable: UInt64 = 5_368_709_120 // 5GB
        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: expectedAvailable
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        let available = await monitor.availableMemory()

        // Assert
        #expect(available == expectedAvailable)
    }
}

// MARK: - Monitoring Lifecycle Tests

@Suite("MemoryMonitor monitoring lifecycle")
struct MemoryMonitorMonitoringLifecycleTests {

    @Test("startMonitoring sets monitoring state")
    func startMonitoringSetsState() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act
        await monitor.startMonitoring { }

        // Assert
        let monitoring = await monitor.isCurrentlyMonitoring
        #expect(monitoring == true)

        // Cleanup
        await monitor.stopMonitoring()
    }

    @Test("stopMonitoring clears state")
    func stopMonitoringClearsState() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)
        await monitor.startMonitoring { }

        // Act
        await monitor.stopMonitoring()

        // Assert
        let monitoring = await monitor.isCurrentlyMonitoring
        #expect(monitoring == false)
    }

    @Test("calling startMonitoring twice does not duplicate observation")
    func startMonitoringIdempotent() async {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 4 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        // Act: start monitoring twice
        await monitor.startMonitoring { }
        await monitor.startMonitoring { }

        // Assert: should still be monitoring
        let monitoring = await monitor.isCurrentlyMonitoring
        #expect(monitoring == true)

        // Cleanup
        await monitor.stopMonitoring()
    }
}

// MARK: - Memory Warning Notification Tests

@Suite("MemoryMonitor memory warning notification")
struct MemoryMonitorNotificationTests {

    @Test("memory warning notification triggers handler")
    func memoryWarningTriggersHandler() async throws {
        // Arrange
        let provider = MockMemoryProvider(
            totalMemory: 8 * 1024 * 1024 * 1024,
            availableMemory: 2 * 1024 * 1024 * 1024
        )
        let monitor = MemoryMonitor(memoryProvider: provider)

        let handlerCalled = AtomicFlag(false)

        await monitor.startMonitoring {
            handlerCalled.set(true)
        }

        // Give the notification listener time to set up
        try await Task.sleep(for: .milliseconds(50))

        // Act: post memory warning notification
        NotificationCenter.default.post(
            name: MemoryMonitor.memoryWarningNotificationName,
            object: nil
        )

        // Wait for async handler to execute
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        #expect(handlerCalled.get() == true)

        // Cleanup
        await monitor.stopMonitoring()
    }
}
