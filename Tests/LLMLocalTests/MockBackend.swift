import LLMLocalClient

/// A mock backend for testing LLMLocalService without requiring real MLX inference.
actor MockBackend: LLMLocalBackend {
    var loadModelCalled = false
    var generateCalled = false
    var unloadCalled = false
    var shouldThrow: LLMLocalError?
    var mockTokens: [String] = ["Hello", " ", "World"]
    private var _isLoaded = false
    private var _currentModel: ModelSpec?

    func loadModel(_ spec: ModelSpec) async throws {
        if let error = shouldThrow { throw error }
        loadModelCalled = true
        _isLoaded = true
        _currentModel = spec
    }

    nonisolated func generate(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.performGenerate(continuation: continuation)
            }
        }
    }

    private func performGenerate(
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        generateCalled = true
        if let error = shouldThrow {
            continuation.finish(throwing: error)
            return
        }
        for token in mockTokens {
            continuation.yield(token)
        }
        continuation.finish()
    }

    func unloadModel() async {
        unloadCalled = true
        _isLoaded = false
        _currentModel = nil
    }

    var isLoaded: Bool { _isLoaded }
    var currentModel: ModelSpec? { _currentModel }

    // MARK: - Test Helpers

    func resetLoadModelCalled() {
        loadModelCalled = false
    }

    func setShouldThrow(_ error: LLMLocalError?) {
        shouldThrow = error
    }

    func setMockTokens(_ tokens: [String]) {
        mockTokens = tokens
    }
}
