import Testing
import Foundation
@testable import LLMLocalClient
@testable import LLMLocalMLX

// MARK: - Test Helpers

/// Mock adapter resolver for testing.
struct MockAdapterResolver: AdapterResolving {
    var resolvedURL: URL
    var shouldThrow: Bool

    init(
        resolvedURL: URL = URL(filePath: "/tmp/adapters/mock-adapter"),
        shouldThrow: Bool = false
    ) {
        self.resolvedURL = resolvedURL
        self.shouldThrow = shouldThrow
    }

    func resolve(_ source: AdapterSource) async throws -> URL {
        if shouldThrow {
            throw LLMLocalError.adapterMergeFailed(reason: "Mock resolution failed")
        }
        return resolvedURL
    }
}

/// Spy adapter resolver that tracks calls for verification.
final class SpyAdapterResolver: AdapterResolving, @unchecked Sendable {
    private let _resolvedURL: URL
    private let _shouldThrow: Bool
    private let lock = NSLock()
    private var _resolvedSources: [AdapterSource] = []

    var resolvedSources: [AdapterSource] {
        lock.withLock { _resolvedSources }
    }

    init(
        resolvedURL: URL = URL(filePath: "/tmp/adapters/spy-adapter"),
        shouldThrow: Bool = false
    ) {
        self._resolvedURL = resolvedURL
        self._shouldThrow = shouldThrow
    }

    func resolve(_ source: AdapterSource) async throws -> URL {
        lock.withLock { _resolvedSources.append(source) }
        if _shouldThrow {
            throw LLMLocalError.adapterMergeFailed(reason: "Spy resolution failed")
        }
        return _resolvedURL
    }
}

/// Helper to create a sample ModelSpec for adapter testing.
private func adapterSpec(
    id: String = "adapter-test-model",
    base: ModelSource = .huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
    adapter: AdapterSource? = .local(path: URL(filePath: "/tmp/adapters/lora")),
    contextLength: Int = 4096,
    displayName: String = "Adapter Test Model",
    description: String = "A test model with adapter"
) -> ModelSpec {
    ModelSpec(
        id: id,
        base: base,
        adapter: adapter,
        contextLength: contextLength,
        displayName: displayName,
        description: description
    )
}

// MARK: - AdapterResolving Protocol Tests

@Suite("AdapterResolving protocol")
struct AdapterResolvingProtocolTests {

    @Test("AdapterResolving protocol exists and is usable")
    func protocolExistsAndIsUsable() {
        // Arrange & Act: compile-time check -- MockAdapterResolver as AdapterResolving
        let resolver: any AdapterResolving = MockAdapterResolver()

        // Assert: if this compiles, the protocol exists and is usable
        #expect(resolver is MockAdapterResolver)
    }

    @Test("AdapterResolving conforms to Sendable")
    func conformsToSendable() {
        // Arrange & Act: compile-time check via Sendable closure boundary
        let resolver = MockAdapterResolver()
        let result: any AdapterResolving = { @Sendable in resolver }()

        // Assert: Sendable conformance verified at compile time
        #expect(result is MockAdapterResolver)
    }

    @Test("Mock resolver resolves adapter source to URL")
    func mockResolverResolvesAdapterSource() async throws {
        // Arrange
        let expectedURL = URL(filePath: "/tmp/adapters/test-adapter")
        let resolver = MockAdapterResolver(resolvedURL: expectedURL)
        let source = AdapterSource.local(path: URL(filePath: "/tmp/adapters/lora"))

        // Act
        let result = try await resolver.resolve(source)

        // Assert
        #expect(result == expectedURL)
    }

    @Test("Mock resolver throws when configured to fail")
    func mockResolverThrowsWhenConfigured() async {
        // Arrange
        let resolver = MockAdapterResolver(shouldThrow: true)
        let source = AdapterSource.local(path: URL(filePath: "/tmp/adapters/lora"))

        // Act & Assert
        await #expect(throws: LLMLocalError.self) {
            try await resolver.resolve(source)
        }
    }
}

// MARK: - MLXBackend Adapter Configuration Tests

@Suite("MLXBackend adapter configuration")
struct MLXBackendAdapterConfigurationTests {

    @Test("Backend created without resolver has nil adapterResolver")
    func backendWithoutResolverHasNilResolver() async {
        // Arrange & Act
        let backend = MLXBackend()

        // Assert
        let hasResolver = await backend.hasAdapterResolver
        #expect(hasResolver == false)
    }

    @Test("Backend created with resolver stores it")
    func backendWithResolverStoresIt() async {
        // Arrange
        let resolver = MockAdapterResolver()

        // Act
        let backend = MLXBackend(adapterResolver: resolver)

        // Assert
        let hasResolver = await backend.hasAdapterResolver
        #expect(hasResolver == true)
    }

    @Test("Backend with resolver preserves default gpuCacheLimit")
    func backendWithResolverPreservesDefaultCacheLimit() async {
        // Arrange & Act
        let resolver = MockAdapterResolver()
        let backend = MLXBackend(adapterResolver: resolver)

        // Assert
        let cacheLimit = await backend.gpuCacheLimitValue
        #expect(cacheLimit == 20 * 1024 * 1024)
    }

    @Test("Backend with resolver and custom gpuCacheLimit")
    func backendWithResolverAndCustomCacheLimit() async {
        // Arrange
        let resolver = MockAdapterResolver()
        let customLimit = 50 * 1024 * 1024

        // Act
        let backend = MLXBackend(gpuCacheLimit: customLimit, adapterResolver: resolver)

        // Assert
        let cacheLimit = await backend.gpuCacheLimitValue
        #expect(cacheLimit == customLimit)
        let hasResolver = await backend.hasAdapterResolver
        #expect(hasResolver == true)
    }
}

// MARK: - resolveAdapter Tests (unit-testable without MLX/Metal)

@Suite("MLXBackend resolveAdapter")
struct MLXBackendResolveAdapterTests {

    @Test("resolveAdapter with adapter but no resolver throws adapterMergeFailed")
    func resolveAdapterWithNoResolverThrows() async {
        // Arrange
        let backend = MLXBackend()
        let spec = adapterSpec()

        // Act & Assert
        await #expect(throws: LLMLocalError.adapterMergeFailed(
            reason: "No adapter resolver configured"
        )) {
            try await backend.resolveAdapter(for: spec)
        }
    }

    @Test("resolveAdapter with adapter calls resolver and returns URL")
    func resolveAdapterCallsResolverAndReturnsURL() async throws {
        // Arrange
        let expectedURL = URL(filePath: "/tmp/adapters/resolved-lora")
        let spy = SpyAdapterResolver(resolvedURL: expectedURL)
        let adapterSource = AdapterSource.local(path: URL(filePath: "/tmp/adapters/lora"))
        let backend = MLXBackend(adapterResolver: spy)
        let spec = adapterSpec(adapter: adapterSource)

        // Act
        let result = try await backend.resolveAdapter(for: spec)

        // Assert: correct URL returned
        #expect(result == expectedURL)

        // Assert: resolver was called with the correct source
        #expect(spy.resolvedSources.count == 1)
        #expect(spy.resolvedSources.first == adapterSource)
    }

    @Test("resolveAdapter with adapter resolution failure propagates LLMLocalError")
    func resolveAdapterPropagatesLLMLocalError() async {
        // Arrange
        let failingResolver = MockAdapterResolver(shouldThrow: true)
        let backend = MLXBackend(adapterResolver: failingResolver)
        let spec = adapterSpec()

        // Act & Assert
        await #expect(throws: LLMLocalError.adapterMergeFailed(
            reason: "Mock resolution failed"
        )) {
            try await backend.resolveAdapter(for: spec)
        }
    }

    @Test("resolveAdapter without adapter returns nil")
    func resolveAdapterWithoutAdapterReturnsNil() async throws {
        // Arrange: spec without adapter, no resolver needed
        let backend = MLXBackend()
        let spec = adapterSpec(adapter: nil)

        // Act
        let result = try await backend.resolveAdapter(for: spec)

        // Assert
        #expect(result == nil)
    }

    @Test("resolveAdapter without adapter does not call resolver")
    func resolveAdapterWithoutAdapterDoesNotCallResolver() async throws {
        // Arrange: resolver provided but spec has no adapter
        let spy = SpyAdapterResolver()
        let backend = MLXBackend(adapterResolver: spy)
        let spec = adapterSpec(adapter: nil)

        // Act
        let result = try await backend.resolveAdapter(for: spec)

        // Assert: resolver should not be called
        #expect(result == nil)
        #expect(spy.resolvedSources.isEmpty)
    }

    @Test("resolveAdapter with gitHubRelease source passes correct source to resolver")
    func resolveAdapterWithGitHubReleaseSource() async throws {
        // Arrange
        let expectedURL = URL(filePath: "/tmp/adapters/gh-adapter")
        let spy = SpyAdapterResolver(resolvedURL: expectedURL)
        let ghSource = AdapterSource.gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
        let backend = MLXBackend(adapterResolver: spy)
        let spec = adapterSpec(adapter: ghSource)

        // Act
        let result = try await backend.resolveAdapter(for: spec)

        // Assert
        #expect(result == expectedURL)
        #expect(spy.resolvedSources.count == 1)
        #expect(spy.resolvedSources.first == ghSource)
    }

    @Test("resolveAdapter with huggingFace source passes correct source to resolver")
    func resolveAdapterWithHuggingFaceSource() async throws {
        // Arrange
        let expectedURL = URL(filePath: "/tmp/adapters/hf-adapter")
        let spy = SpyAdapterResolver(resolvedURL: expectedURL)
        let hfSource = AdapterSource.huggingFace(id: "user/my-lora-adapter")
        let backend = MLXBackend(adapterResolver: spy)
        let spec = adapterSpec(adapter: hfSource)

        // Act
        let result = try await backend.resolveAdapter(for: spec)

        // Assert
        #expect(result == expectedURL)
        #expect(spy.resolvedSources.count == 1)
        #expect(spy.resolvedSources.first == hfSource)
    }

    @Test("resolveAdapter wraps non-LLMLocalError in adapterMergeFailed")
    func resolveAdapterWrapsGenericError() async {
        // Arrange: resolver that throws a generic (non-LLMLocalError) error
        let backend = MLXBackend(adapterResolver: GenericErrorResolver())
        let spec = adapterSpec()

        // Act & Assert: generic error should be wrapped in adapterMergeFailed
        await #expect(throws: LLMLocalError.self) {
            try await backend.resolveAdapter(for: spec)
        }
    }
}

/// Resolver that throws a generic (non-LLMLocalError) error, for testing wrapping behavior.
private struct GenericErrorResolver: AdapterResolving {
    struct GenericError: Error, CustomStringConvertible {
        let description = "Something went wrong"
    }

    func resolve(_ source: AdapterSource) async throws -> URL {
        throw GenericError()
    }
}

// MARK: - loadModel Adapter Integration Tests (error paths only)

@Suite("MLXBackend loadModel adapter error paths")
struct MLXBackendLoadModelAdapterErrorPathTests {

    @Test("loadModel with adapter but no resolver throws adapterMergeFailed")
    func loadModelWithAdapterButNoResolverThrows() async {
        // Arrange: no resolver configured, but spec has adapter
        let backend = MLXBackend()
        let spec = adapterSpec()

        // Act & Assert: should throw before reaching MLX APIs
        await #expect(throws: LLMLocalError.adapterMergeFailed(
            reason: "No adapter resolver configured"
        )) {
            try await backend.loadModel(spec)
        }
    }

    @Test("loadModel with adapter resolution failure propagates error")
    func loadModelWithAdapterResolutionFailurePropagates() async {
        // Arrange
        let failingResolver = MockAdapterResolver(shouldThrow: true)
        let backend = MLXBackend(adapterResolver: failingResolver)
        let spec = adapterSpec()

        // Act & Assert: should throw before reaching MLX APIs
        await #expect(throws: LLMLocalError.self) {
            try await backend.loadModel(spec)
        }
    }

    @Test("loadModel resets lastResolvedAdapterURL before resolving")
    func loadModelResetsAdapterURL() async {
        // Arrange: backend with no resolver, adapter spec will fail
        let backend = MLXBackend()
        let spec = adapterSpec()

        // Act
        do {
            try await backend.loadModel(spec)
        } catch {
            // Expected: adapterMergeFailed
        }

        // Assert: lastResolvedAdapterURL should be nil (reset happened, resolution failed)
        let url = await backend.lastResolvedAdapterURL
        #expect(url == nil)
    }
}

// MARK: - Backward Compatibility Tests

@Suite("MLXBackend backward compatibility")
struct MLXBackendBackwardCompatibilityTests {

    @Test("init without adapterResolver maintains original API")
    func initWithoutAdapterResolverMaintainsAPI() async {
        // Arrange & Act: original init signature still works
        let backend = MLXBackend()

        // Assert: no adapter resolver, same defaults
        let hasResolver = await backend.hasAdapterResolver
        let cacheLimit = await backend.gpuCacheLimitValue
        let loaded = await backend.isLoaded
        let model = await backend.currentModel

        #expect(hasResolver == false)
        #expect(cacheLimit == 20 * 1024 * 1024)
        #expect(loaded == false)
        #expect(model == nil)
    }

    @Test("init with custom gpuCacheLimit still works without adapterResolver")
    func initWithCustomCacheLimitStillWorks() async {
        // Arrange & Act
        let customLimit = 50 * 1024 * 1024
        let backend = MLXBackend(gpuCacheLimit: customLimit)

        // Assert
        let cacheLimit = await backend.gpuCacheLimitValue
        let hasResolver = await backend.hasAdapterResolver
        #expect(cacheLimit == customLimit)
        #expect(hasResolver == false)
    }

    @Test("ModelSpec without adapter does not trigger adapter resolution")
    func modelSpecWithoutAdapterSkipsResolution() async throws {
        // Arrange: spec without adapter
        let spy = SpyAdapterResolver()
        let backend = MLXBackend(adapterResolver: spy)
        let spec = adapterSpec(adapter: nil)

        // Act: resolveAdapter should return nil and not call the resolver
        let result = try await backend.resolveAdapter(for: spec)

        // Assert
        #expect(result == nil)
        #expect(spy.resolvedSources.isEmpty)
    }
}
