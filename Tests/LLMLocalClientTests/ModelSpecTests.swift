import Testing
import Foundation
import LLMLocalClient

// MARK: - ModelSource Tests

@Suite("ModelSource")
struct ModelSourceTests {

    @Test("huggingFace sources with same id are equal")
    func huggingFaceSameIdAreEqual() {
        let a = ModelSource.huggingFace(id: "mlx-community/Llama-3.2-1B")
        let b = ModelSource.huggingFace(id: "mlx-community/Llama-3.2-1B")
        #expect(a == b)
    }

    @Test("huggingFace sources with different ids are not equal")
    func huggingFaceDifferentIdsAreNotEqual() {
        let a = ModelSource.huggingFace(id: "mlx-community/Llama-3.2-1B")
        let b = ModelSource.huggingFace(id: "mlx-community/Mistral-7B")
        #expect(a != b)
    }

    @Test("local sources with same path are equal")
    func localSamePathAreEqual() {
        let url = URL(filePath: "/tmp/models/llama")
        let a = ModelSource.local(path: url)
        let b = ModelSource.local(path: url)
        #expect(a == b)
    }

    @Test("local sources with different paths are not equal")
    func localDifferentPathsAreNotEqual() {
        let a = ModelSource.local(path: URL(filePath: "/tmp/models/llama"))
        let b = ModelSource.local(path: URL(filePath: "/tmp/models/mistral"))
        #expect(a != b)
    }

    @Test("huggingFace and local are not equal")
    func huggingFaceAndLocalAreNotEqual() {
        let a = ModelSource.huggingFace(id: "mlx-community/Llama-3.2-1B")
        let b = ModelSource.local(path: URL(filePath: "/tmp/models/llama"))
        #expect(a != b)
    }

    @Test("huggingFace Codable round-trip preserves value")
    func huggingFaceCodableRoundTrip() throws {
        let original = ModelSource.huggingFace(id: "mlx-community/Llama-3.2-1B")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelSource.self, from: data)
        #expect(original == decoded)
    }

    @Test("local Codable round-trip preserves value")
    func localCodableRoundTrip() throws {
        let original = ModelSource.local(path: URL(filePath: "/tmp/models/llama"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelSource.self, from: data)
        #expect(original == decoded)
    }

    @Test("ModelSource conforms to Sendable")
    func conformsToSendable() async {
        let source = ModelSource.huggingFace(id: "test")
        // Passing across a Sendable closure boundary proves Sendable conformance at compile time
        let result: ModelSource = { @Sendable in source }()
        #expect(result == source)
    }
}

// MARK: - AdapterSource Tests

@Suite("AdapterSource")
struct AdapterSourceTests {

    @Test("gitHubRelease sources with same values are equal")
    func gitHubReleaseSameValuesAreEqual() {
        let a = AdapterSource.gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
        let b = AdapterSource.gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
        #expect(a == b)
    }

    @Test("gitHubRelease sources with different tags are not equal")
    func gitHubReleaseDifferentTagsAreNotEqual() {
        let a = AdapterSource.gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
        let b = AdapterSource.gitHubRelease(repo: "owner/repo", tag: "v2.0", asset: "adapter.safetensors")
        #expect(a != b)
    }

    @Test("huggingFace adapter sources with same id are equal")
    func huggingFaceSameIdAreEqual() {
        let a = AdapterSource.huggingFace(id: "user/adapter-1")
        let b = AdapterSource.huggingFace(id: "user/adapter-1")
        #expect(a == b)
    }

    @Test("local adapter sources with same path are equal")
    func localSamePathAreEqual() {
        let url = URL(filePath: "/tmp/adapters/lora")
        let a = AdapterSource.local(path: url)
        let b = AdapterSource.local(path: url)
        #expect(a == b)
    }

    @Test("different adapter source types are not equal")
    func differentTypesAreNotEqual() {
        let a = AdapterSource.huggingFace(id: "user/adapter-1")
        let b = AdapterSource.local(path: URL(filePath: "/tmp/adapters/lora"))
        #expect(a != b)
    }

    @Test("gitHubRelease Codable round-trip preserves value")
    func gitHubReleaseCodableRoundTrip() throws {
        let original = AdapterSource.gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AdapterSource.self, from: data)
        #expect(original == decoded)
    }

    @Test("huggingFace adapter Codable round-trip preserves value")
    func huggingFaceCodableRoundTrip() throws {
        let original = AdapterSource.huggingFace(id: "user/adapter-1")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AdapterSource.self, from: data)
        #expect(original == decoded)
    }

    @Test("local adapter Codable round-trip preserves value")
    func localCodableRoundTrip() throws {
        let original = AdapterSource.local(path: URL(filePath: "/tmp/adapters/lora"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AdapterSource.self, from: data)
        #expect(original == decoded)
    }

    @Test("AdapterSource conforms to Sendable")
    func conformsToSendable() {
        let source = AdapterSource.huggingFace(id: "test")
        let result: AdapterSource = { @Sendable in source }()
        #expect(result == source)
    }
}

// MARK: - ModelSpec Tests

@Suite("ModelSpec")
struct ModelSpecTests {

    // MARK: - Test Helpers

    static func sampleSpec(
        id: String = "llama-3.2-1b",
        base: ModelSource = .huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
        adapter: AdapterSource? = nil,
        contextLength: Int = 4096,
        displayName: String = "Llama 3.2 1B",
        description: String = "Lightweight model for on-device inference",
        estimatedMemoryBytes: UInt64 = 4_500_000_000
    ) -> ModelSpec {
        ModelSpec(
            id: id,
            base: base,
            adapter: adapter,
            contextLength: contextLength,
            displayName: displayName,
            description: description,
            estimatedMemoryBytes: estimatedMemoryBytes
        )
    }

    // MARK: - Initialization

    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        let adapter = AdapterSource.gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors")
        let spec = ModelSpec(
            id: "test-model",
            base: .huggingFace(id: "mlx-community/test"),
            adapter: adapter,
            contextLength: 2048,
            displayName: "Test Model",
            description: "A test model",
            estimatedMemoryBytes: 4_500_000_000
        )

        #expect(spec.id == "test-model")
        #expect(spec.base == .huggingFace(id: "mlx-community/test"))
        #expect(spec.adapter == adapter)
        #expect(spec.contextLength == 2048)
        #expect(spec.displayName == "Test Model")
        #expect(spec.description == "A test model")
        #expect(spec.estimatedMemoryBytes == 4_500_000_000)
    }

    @Test("initializes with nil adapter by default")
    func initializesWithNilAdapterByDefault() {
        let spec = ModelSpec(
            id: "test-model",
            base: .huggingFace(id: "mlx-community/test"),
            contextLength: 2048,
            displayName: "Test Model",
            description: "A test model",
            estimatedMemoryBytes: 4_500_000_000
        )

        #expect(spec.adapter == nil)
    }

    // MARK: - Hashable

    @Test("specs with same id and base are equal")
    func specsWithSameValuesAreEqual() {
        let a = Self.sampleSpec()
        let b = Self.sampleSpec()
        #expect(a == b)
    }

    @Test("specs with different ids are not equal")
    func specsWithDifferentIdsAreNotEqual() {
        let a = Self.sampleSpec(id: "model-a")
        let b = Self.sampleSpec(id: "model-b")
        #expect(a != b)
    }

    @Test("specs with different base sources are not equal")
    func specsWithDifferentBasesAreNotEqual() {
        let a = Self.sampleSpec(base: .huggingFace(id: "model-a"))
        let b = Self.sampleSpec(base: .huggingFace(id: "model-b"))
        #expect(a != b)
    }

    @Test("specs with different adapters are not equal")
    func specsWithDifferentAdaptersAreNotEqual() {
        let a = Self.sampleSpec(adapter: nil)
        let b = Self.sampleSpec(adapter: .huggingFace(id: "adapter-1"))
        #expect(a != b)
    }

    @Test("equal specs produce same hash value")
    func equalSpecsProduceSameHash() {
        let a = Self.sampleSpec()
        let b = Self.sampleSpec()
        #expect(a.hashValue == b.hashValue)
    }

    @Test("can be used as Set element")
    func canBeUsedAsSetElement() {
        let spec1 = Self.sampleSpec(id: "model-1")
        let spec2 = Self.sampleSpec(id: "model-2")
        let spec1Duplicate = Self.sampleSpec(id: "model-1")

        var set: Set<ModelSpec> = []
        set.insert(spec1)
        set.insert(spec2)
        set.insert(spec1Duplicate)

        #expect(set.count == 2)
    }

    @Test("can be used as Dictionary key")
    func canBeUsedAsDictionaryKey() {
        let spec = Self.sampleSpec()
        var dict: [ModelSpec: String] = [:]
        dict[spec] = "loaded"

        #expect(dict[spec] == "loaded")
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves all properties")
    func codableRoundTripPreservesAllProperties() throws {
        let original = ModelSpec(
            id: "llama-3.2-1b",
            base: .huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
            adapter: .gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"),
            contextLength: 4096,
            displayName: "Llama 3.2 1B",
            description: "Lightweight model",
            estimatedMemoryBytes: 4_500_000_000
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ModelSpec.self, from: data)

        #expect(original == decoded)
        #expect(decoded.id == "llama-3.2-1b")
        #expect(decoded.base == .huggingFace(id: "mlx-community/Llama-3.2-1B-Instruct-4bit"))
        #expect(decoded.adapter == .gitHubRelease(repo: "owner/repo", tag: "v1.0", asset: "adapter.safetensors"))
        #expect(decoded.contextLength == 4096)
        #expect(decoded.displayName == "Llama 3.2 1B")
        #expect(decoded.description == "Lightweight model")
        #expect(decoded.estimatedMemoryBytes == 4_500_000_000)
    }

    @Test("Codable round-trip preserves nil adapter")
    func codableRoundTripPreservesNilAdapter() throws {
        let original = Self.sampleSpec(adapter: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelSpec.self, from: data)

        #expect(original == decoded)
        #expect(decoded.adapter == nil)
    }

    @Test("Codable round-trip with local base source")
    func codableRoundTripWithLocalBase() throws {
        let original = Self.sampleSpec(
            base: .local(path: URL(filePath: "/tmp/models/llama"))
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelSpec.self, from: data)

        #expect(original == decoded)
    }

    @Test("Codable round-trip with local adapter source")
    func codableRoundTripWithLocalAdapter() throws {
        let original = Self.sampleSpec(
            adapter: .local(path: URL(filePath: "/tmp/adapters/lora"))
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelSpec.self, from: data)

        #expect(original == decoded)
    }

    // MARK: - estimatedMemoryBytes

    @Test("Codable round-trip preserves estimatedMemoryBytes")
    func codableRoundTripPreservesEstimatedMemoryBytes() throws {
        let original = Self.sampleSpec(estimatedMemoryBytes: 7_000_000_000)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelSpec.self, from: data)

        #expect(original == decoded)
        #expect(decoded.estimatedMemoryBytes == 7_000_000_000)
    }

    // MARK: - formattedMemorySize

    @Test("formattedMemorySize returns human readable string")
    func formattedMemorySizeReturnsString() {
        let spec = Self.sampleSpec(estimatedMemoryBytes: 4_500_000_000)
        let formatted = spec.formattedMemorySize
        #expect(formatted.contains("GB"))
    }

    // MARK: - sizeTier

    @Test("sizeTier returns tiny for sub-1GB model")
    func sizeTierReturnsTiny() {
        let spec = Self.sampleSpec(estimatedMemoryBytes: 500_000_000)
        #expect(spec.sizeTier == .tiny)
    }

    @Test("sizeTier returns medium for 5GB model")
    func sizeTierReturnsMedium() {
        let spec = Self.sampleSpec(estimatedMemoryBytes: 5_000_000_000)
        #expect(spec.sizeTier == .medium)
    }

    // MARK: - Sendable

    @Test("ModelSpec conforms to Sendable")
    func conformsToSendable() {
        let spec = Self.sampleSpec()
        let result: ModelSpec = { @Sendable in spec }()
        #expect(result == spec)
    }
}

// MARK: - LLMLocalBackend Protocol Tests

@Suite("LLMLocalBackend protocol")
struct LLMLocalBackendTests {

    /// A mock backend implemented as an actor to verify the protocol contract.
    /// Uses nonisolated for synchronous protocol requirements.
    actor MockBackend: LLMLocalBackend {
        private var _isLoaded: Bool = false
        private var _currentModel: ModelSpec?

        var isLoaded: Bool { _isLoaded }
        var currentModel: ModelSpec? { _currentModel }

        func loadModel(_ spec: ModelSpec) async throws {
            _currentModel = spec
            _isLoaded = true
        }

        nonisolated func generate(prompt: String, config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield("Hello")
                continuation.yield(" World")
                continuation.finish()
            }
        }

        func unloadModel() async {
            _currentModel = nil
            _isLoaded = false
        }
    }

    let backend: MockBackend

    init() {
        backend = MockBackend()
    }

    @Test("initially not loaded")
    func initiallyNotLoaded() async {
        let loaded = await backend.isLoaded
        #expect(loaded == false)
    }

    @Test("initially has no current model")
    func initiallyHasNoCurrentModel() async {
        let model = await backend.currentModel
        #expect(model == nil)
    }

    @Test("loadModel sets current model and isLoaded")
    func loadModelSetsState() async throws {
        let spec = ModelSpec(
            id: "test-model",
            base: .huggingFace(id: "mlx-community/test"),
            contextLength: 2048,
            displayName: "Test",
            description: "Test model",
            estimatedMemoryBytes: 4_500_000_000
        )

        try await backend.loadModel(spec)

        let loaded = await backend.isLoaded
        let currentModel = await backend.currentModel
        #expect(loaded == true)
        #expect(currentModel == spec)
    }

    @Test("unloadModel clears state")
    func unloadModelClearsState() async throws {
        let spec = ModelSpec(
            id: "test-model",
            base: .huggingFace(id: "mlx-community/test"),
            contextLength: 2048,
            displayName: "Test",
            description: "Test model",
            estimatedMemoryBytes: 4_500_000_000
        )

        try await backend.loadModel(spec)
        await backend.unloadModel()

        let loaded = await backend.isLoaded
        let currentModel = await backend.currentModel
        #expect(loaded == false)
        #expect(currentModel == nil)
    }

    @Test("generate returns async stream of tokens")
    func generateReturnsAsyncStream() async throws {
        var tokens: [String] = []
        let stream = backend.generate(prompt: "Hello", config: .default)

        for try await token in stream {
            tokens.append(token)
        }

        #expect(tokens == ["Hello", " World"])
    }
}
