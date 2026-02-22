import Testing
@testable import LLMLocalClient

@Suite("GenerationConfig")
struct GenerationConfigTests {

    // MARK: - Default values

    @Test("default config has maxTokens 1024")
    func defaultMaxTokens() {
        let config = GenerationConfig.default
        #expect(config.maxTokens == 1024)
    }

    @Test("default config has temperature 0.7")
    func defaultTemperature() {
        let config = GenerationConfig.default
        #expect(config.temperature == 0.7)
    }

    @Test("default config has topP 0.9")
    func defaultTopP() {
        let config = GenerationConfig.default
        #expect(config.topP == 0.9)
    }

    // MARK: - Init with default parameters

    @Test("init without arguments uses default values")
    func initWithoutArguments() {
        let config = GenerationConfig()
        #expect(config.maxTokens == 1024)
        #expect(config.temperature == 0.7)
        #expect(config.topP == 0.9)
    }

    // MARK: - Custom values

    @Test("init with custom maxTokens")
    func customMaxTokens() {
        let config = GenerationConfig(maxTokens: 2048)
        #expect(config.maxTokens == 2048)
        #expect(config.temperature == 0.7)
        #expect(config.topP == 0.9)
    }

    @Test("init with custom temperature")
    func customTemperature() {
        let config = GenerationConfig(temperature: 0.5)
        #expect(config.maxTokens == 1024)
        #expect(config.temperature == 0.5)
        #expect(config.topP == 0.9)
    }

    @Test("init with custom topP")
    func customTopP() {
        let config = GenerationConfig(topP: 0.95)
        #expect(config.maxTokens == 1024)
        #expect(config.temperature == 0.7)
        #expect(config.topP == 0.95)
    }

    @Test("init with all custom values")
    func allCustomValues() {
        let config = GenerationConfig(maxTokens: 512, temperature: 0.3, topP: 0.8)
        #expect(config.maxTokens == 512)
        #expect(config.temperature == 0.3)
        #expect(config.topP == 0.8)
    }

    // MARK: - Mutability

    @Test("properties are mutable")
    func propertiesAreMutable() {
        var config = GenerationConfig()
        config.maxTokens = 4096
        config.temperature = 1.0
        config.topP = 0.5
        #expect(config.maxTokens == 4096)
        #expect(config.temperature == 1.0)
        #expect(config.topP == 0.5)
    }

    // MARK: - Sendable (compile-time check)

    @Test("config is Sendable")
    func sendableCheck() async {
        let config = GenerationConfig()
        // If this compiles, GenerationConfig conforms to Sendable.
        let result = await sendAcrossBoundary(config)
        #expect(result.maxTokens == 1024)
    }
}

// Helper to verify Sendable conformance at compile time.
private func sendAcrossBoundary<T: Sendable>(_ value: T) async -> T {
    value
}
