import Testing
@testable import LLMLocalClient

@Suite("GenerationStats")
struct GenerationStatsTests {

    // MARK: - Init and property access

    @Test("stores tokenCount correctly")
    func tokenCount() {
        let stats = GenerationStats(
            tokenCount: 150,
            tokensPerSecond: 45.5,
            duration: .seconds(3)
        )
        #expect(stats.tokenCount == 150)
    }

    @Test("stores tokensPerSecond correctly")
    func tokensPerSecond() {
        let stats = GenerationStats(
            tokenCount: 150,
            tokensPerSecond: 45.5,
            duration: .seconds(3)
        )
        #expect(stats.tokensPerSecond == 45.5)
    }

    @Test("stores duration correctly")
    func duration() {
        let stats = GenerationStats(
            tokenCount: 150,
            tokensPerSecond: 45.5,
            duration: .seconds(3)
        )
        #expect(stats.duration == .seconds(3))
    }

    // MARK: - Edge cases

    @Test("handles zero tokenCount")
    func zeroTokenCount() {
        let stats = GenerationStats(
            tokenCount: 0,
            tokensPerSecond: 0.0,
            duration: .zero
        )
        #expect(stats.tokenCount == 0)
        #expect(stats.tokensPerSecond == 0.0)
        #expect(stats.duration == .zero)
    }

    @Test("handles large tokenCount")
    func largeTokenCount() {
        let stats = GenerationStats(
            tokenCount: 100_000,
            tokensPerSecond: 120.75,
            duration: .seconds(828)
        )
        #expect(stats.tokenCount == 100_000)
        #expect(stats.tokensPerSecond == 120.75)
    }

    @Test("handles sub-second duration")
    func subSecondDuration() {
        let stats = GenerationStats(
            tokenCount: 10,
            tokensPerSecond: 200.0,
            duration: .milliseconds(50)
        )
        #expect(stats.duration == .milliseconds(50))
    }

    // MARK: - Immutability (let properties)

    // No mutation test needed: properties are `let`, so attempting mutation would be a compile error.

    // MARK: - Sendable (compile-time check)

    @Test("stats is Sendable")
    func sendableCheck() async {
        let stats = GenerationStats(
            tokenCount: 100,
            tokensPerSecond: 50.0,
            duration: .seconds(2)
        )
        let result = await sendAcrossBoundary(stats)
        #expect(result.tokenCount == 100)
    }
}

// Helper to verify Sendable conformance at compile time.
private func sendAcrossBoundary<T: Sendable>(_ value: T) async -> T {
    value
}
