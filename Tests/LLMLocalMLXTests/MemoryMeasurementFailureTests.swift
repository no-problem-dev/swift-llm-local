import Foundation
import Testing
@testable import LLMLocalClient
@testable import LLMLocalMLX

// MARK: - Providers

/// Reports numbers that are real measurements.
private struct FixedMemoryProvider: MemoryProvider, Sendable {
    let total: UInt64
    let available: UInt64

    func totalMemoryBytes() -> UInt64 { total }
    func availableMemoryBytes() throws -> UInt64 { available }
}

/// Cannot take a measurement at all — the kernel query failed.
private struct UnreadableMemoryProvider: MemoryProvider, Sendable {
    let total: UInt64 = 8 * 1024 * 1024 * 1024

    func totalMemoryBytes() -> UInt64 { total }
    func availableMemoryBytes() throws -> UInt64 {
        throw LLMLocalError.memoryUnreadable(
            reason: "host_page_size failed with kern_return_t 5."
        )
    }
}

private func errorThrown(by operation: () async throws -> Void) async -> (any Error)? {
    do {
        try await operation()
        return nil
    } catch {
        return error
    }
}

private func isMemoryUnreadable(_ error: (any Error)?) -> Bool {
    if case .memoryUnreadable = error as? LLMLocalError { return true }
    return false
}

// MARK: - Tests

/// A memory number that was never measured must not reach an admission decision.
///
/// The decision this feeds is whether to load multi-gigabyte weights into a process jetsam will
/// kill for exceeding its budget. Both directions of a fabricated answer are damaging, and the
/// tests below pin both: a low guess rejects every model on a device that could run them, and a
/// high guess loads weights that terminate the app.
@Suite("Memory measurement failure")
struct MemoryMeasurementFailureTests {

    private static func spec(estimatedMemoryBytes: UInt64) -> ModelSpec {
        ModelSpec(
            id: "test-model",
            base: .huggingFace(id: "mlx-community/Test"),
            contextLength: 4096,
            displayName: "Test",
            description: "",
            estimatedMemoryBytes: estimatedMemoryBytes
        )
    }

    /// The measurement itself: a failure must not come back as a number.
    ///
    /// Half of physical memory was the old stand-in for a failed `host_statistics64`, and a
    /// discarded `host_page_size` return code produced a page size of zero and therefore an
    /// available figure of zero. Both are values in exactly the right shape, and nothing about
    /// either says it was invented.
    @Test("available memory that could not be measured is not a number")
    func availableMemoryDoesNotGuess() async throws {
        // Arrange: same call, two monitors — one that can measure, one that cannot.
        let measured = MemoryMonitor(
            memoryProvider: FixedMemoryProvider(
                total: 8 * 1024 * 1024 * 1024, available: 3 * 1024 * 1024 * 1024
            )
        )
        let unmeasurable = MemoryMonitor(memoryProvider: UnreadableMemoryProvider())

        // Act
        let available = try await measured.availableMemory()
        let error = await errorThrown { _ = try await unmeasurable.availableMemory() }

        // Assert
        #expect(available == 3 * 1024 * 1024 * 1024)
        #expect(isMemoryUnreadable(error), "got \(String(describing: error))")
    }

    /// The admission decision, on whichever platform's budget the host is compiled for.
    ///
    /// The two platforms take the budget from different places, and only one of them is downstream
    /// of the failing measurement:
    ///
    /// - **iOS, tvOS, watchOS**: the budget is 80% of memory the process may still allocate, so an
    ///   unmeasurable provider reaches the decision directly. That is the jetsam path, and a
    ///   fabricated zero there answers `false` for every model on the device — indistinguishable
    ///   from a model that genuinely will not fit.
    /// - **macOS**: the budget is 80% of physical memory, which is read from `ProcessInfo` and
    ///   cannot fail, so the decision is unaffected. The failing Mach code is macOS-only, which
    ///   means `SystemMemoryProvider` cannot produce the iOS case itself — but any provider an app
    ///   injects can, and until now the protocol gave it no way to say so.
    @Test("a budget that could not be read is not a budget of zero")
    func unreadableIsNotZeroBudget() async throws {
        // Arrange
        let unmeasurable = MemoryMonitor(memoryProvider: UnreadableMemoryProvider())
        let spec = Self.spec(estimatedMemoryBytes: 6 * 1024 * 1024 * 1024)

        // Act
        let budgetError = await errorThrown { _ = try await unmeasurable.maxAllowedModelMemory() }
        let fitError = await errorThrown { _ = try await unmeasurable.isModelCompatible(spec) }

        // Assert
        #if os(iOS) || os(tvOS) || os(watchOS)
        #expect(isMemoryUnreadable(budgetError), "got \(String(describing: budgetError))")
        #expect(
            isMemoryUnreadable(fitError),
            """
            false is the answer for a model too large for the device, and it would be given for \
            every model; got \(String(describing: fitError))
            """
        )
        #else
        #expect(budgetError == nil, "the macOS budget comes from physical memory, which cannot fail")
        #expect(fitError == nil)
        #endif
    }

    @Test("a real measurement still decides both ways")
    func realMeasurementsStillDecide() async throws {
        // Arrange: 8 GB either way, so the budget is 6.4 GB on both platforms.
        let monitor = MemoryMonitor(
            memoryProvider: FixedMemoryProvider(
                total: 8 * 1024 * 1024 * 1024, available: 8 * 1024 * 1024 * 1024
            )
        )

        // Act & Assert
        #expect(try await monitor.isModelCompatible(Self.spec(estimatedMemoryBytes: 1_000_000_000)))
        #expect(
            try await monitor.isModelCompatible(
                Self.spec(estimatedMemoryBytes: 7 * 1024 * 1024 * 1024)
            ) == false
        )
    }

    /// The provider that runs in production, exercised against the machine running the tests.
    ///
    /// A `host_page_size` failure used to be discarded outright, leaving a page size of zero and
    /// this number at zero. Asserting it is positive on a live host is the cheapest evidence that
    /// the return code is now checked and the page size is not zero.
    @Test("the system provider reports a real number on this host")
    func systemProviderMeasuresSomething() throws {
        let provider = SystemMemoryProvider()
        #expect(provider.totalMemoryBytes() > 0)
        #expect(try provider.availableMemoryBytes() > 0)
    }
}
