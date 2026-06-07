import LLMClient
import LLMLocalClient

/// A mock backend for testing LLMLocalService without requiring real MLX inference.
actor MockBackend: LLMLocalBackend {
    var loadModelCalled = false
    var generateCalled = false
    var generateWithToolsCalled = false
    var generateFromMessagesCalled = false
    var unloadCalled = false
    var shouldThrow: LLMLocalError?
    var mockTokens: [String] = ["Hello", " ", "World"]
    var mockToolOutputs: [GenerationOutput]?
    var lastToolDefinitions: [ToolDefinition]?
    var lastMessages: [LLMMessage]?
    var lastSystemPrompt: String?
    var lastConfig: GenerationConfig?
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
                await self.performGenerate(config: config, continuation: continuation)
            }
        }
    }

    private func performGenerate(
        config: GenerationConfig,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        generateCalled = true
        lastConfig = config
        if let error = shouldThrow {
            continuation.finish(throwing: error)
            return
        }
        for token in mockTokens {
            continuation.yield(token)
        }
        continuation.finish()
    }

    nonisolated func generateWithTools(
        prompt: String,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.performToolOutputs(
                    config: config, tools: tools, continuation: continuation
                ) {
                    await self.markGenerateWithToolsCalled()
                }
            }
        }
    }

    nonisolated func generateFromMessages(
        messages: [LLMMessage],
        systemPrompt: String?,
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<GenerationOutput, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.performToolOutputs(
                    config: config, tools: tools, continuation: continuation
                ) {
                    await self.markGenerateFromMessagesCalled(
                        messages: messages, systemPrompt: systemPrompt
                    )
                }
            }
        }
    }

    private func performToolOutputs(
        config: GenerationConfig,
        tools: [ToolDefinition],
        continuation: AsyncThrowingStream<GenerationOutput, Error>.Continuation,
        mark: () async -> Void
    ) async {
        await mark()
        lastConfig = config
        lastToolDefinitions = tools
        if let error = shouldThrow {
            continuation.finish(throwing: error)
            return
        }
        if let outputs = mockToolOutputs {
            for output in outputs {
                continuation.yield(output)
            }
        } else {
            for token in mockTokens {
                continuation.yield(.text(token))
            }
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

    private func markGenerateWithToolsCalled() {
        generateWithToolsCalled = true
    }

    private func markGenerateFromMessagesCalled(
        messages: [LLMMessage],
        systemPrompt: String?
    ) {
        generateFromMessagesCalled = true
        lastMessages = messages
        lastSystemPrompt = systemPrompt
    }

    func resetLoadModelCalled() {
        loadModelCalled = false
    }

    func setShouldThrow(_ error: LLMLocalError?) {
        shouldThrow = error
    }

    func setMockTokens(_ tokens: [String]) {
        mockTokens = tokens
    }

    func setMockToolOutputs(_ outputs: [GenerationOutput]) {
        mockToolOutputs = outputs
    }
}
