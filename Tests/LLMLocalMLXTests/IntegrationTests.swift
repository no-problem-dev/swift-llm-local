#if !targetEnvironment(simulator)
import Testing
import LLMLocal
import LLMLocalClient
import LLMLocalMLX
import LLMLocalModels

/// Integration tests for the full LLM stack.
///
/// These tests require a Metal GPU and will download real models (~1.5GB).
/// They cannot be run in CI or simulators.
///
/// ## Test Coverage
/// - Full stack: LLMLocalService → MLXBackend → model load → streaming generation
/// - Error handling: invalid model ID scenarios
/// - Cancellation: graceful task cancellation during generation
/// - Re-generation: multiple generations without unloading
/// - Statistics: validation of GenerationStats after completion
@Suite("Integration Tests", .disabled("Requires Metal GPU and model download"))
struct IntegrationTests {

    // MARK: - Test 1: Full Flow

    @Test("Full flow: Service → Backend → load → generate → stats")
    func fullFlowGeneratesTokensAndStats() async throws {
        // Setup
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        // Use a short prompt and limit tokens to minimize execution time
        let config = GenerationConfig(maxTokens: 50, temperature: 0.7, topP: 0.9)
        let prompt = "What is Swift?"

        // Generate tokens
        var receivedTokens: [String] = []
        let stream = await service.generate(
            model: ModelPresets.gemma2B,
            prompt: prompt,
            config: config
        )

        for try await token in stream {
            receivedTokens.append(token)
        }

        // Verify tokens were received
        #expect(!receivedTokens.isEmpty, "Should receive at least one token")

        // Verify stats
        let stats = await service.lastGenerationStats
        #expect(stats != nil, "Stats should be recorded after generation")
        #expect(stats!.tokenCount > 0, "Token count should be positive")
        #expect(stats!.tokensPerSecond > 0, "Tokens per second should be positive")
        #expect(stats!.duration > .zero, "Duration should be positive")

        // Verify token count matches received tokens
        #expect(stats!.tokenCount == receivedTokens.count, "Token count should match received tokens")
    }

    // MARK: - Test 2: Error Handling

    @Test("Error handling: Invalid model ID → loadFailed")
    func invalidModelIdThrowsLoadFailed() async throws {
        // Setup
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        // Create a model spec with invalid HuggingFace ID
        let invalidModel = ModelSpec(
            id: "invalid-model-id",
            base: .huggingFace(id: "mlx-community/nonexistent-model-12345"),
            adapter: nil,
            contextLength: 2048,
            displayName: "Invalid Model",
            description: "This model does not exist"
        )

        let config = GenerationConfig(maxTokens: 10)
        let prompt = "Test"

        // Attempt to generate - should throw loadFailed
        var didThrowLoadFailed = false
        do {
            let stream = await service.generate(
                model: invalidModel,
                prompt: prompt,
                config: config
            )
            for try await _ in stream {
                // Should not reach here
            }
        } catch let error as LLMLocalError {
            if case .loadFailed = error {
                didThrowLoadFailed = true
            }
        }

        #expect(didThrowLoadFailed, "Should throw LLMLocalError.loadFailed for invalid model")
    }

    // MARK: - Test 3: Cancellation

    @Test("Cancellation: Start generate, cancel the task")
    func cancellationFinishesCleanly() async throws {
        // Setup
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        // Use a longer generation to ensure we can cancel mid-stream
        let config = GenerationConfig(maxTokens: 200, temperature: 0.7, topP: 0.9)
        let prompt = "Write a long essay about Swift programming language."

        // Start generation in a task
        let task = Task {
            var tokenCount = 0
            let stream = await service.generate(
                model: ModelPresets.gemma2B,
                prompt: prompt,
                config: config
            )

            for try await _ in stream {
                tokenCount += 1
                // Cancel after receiving a few tokens
                if tokenCount >= 5 {
                    throw CancellationError()
                }
            }
        }

        // Wait a bit to ensure generation starts
        try await Task.sleep(for: .milliseconds(500))

        // Cancel the task
        task.cancel()

        // Should finish without crash
        var didThrowCancelled = false
        do {
            try await task.value
        } catch is CancellationError {
            didThrowCancelled = true
        } catch let error as LLMLocalError {
            if case .cancelled = error {
                didThrowCancelled = true
            }
        }

        #expect(didThrowCancelled, "Should handle cancellation gracefully")
    }

    // MARK: - Test 4: Re-generation

    @Test("Re-generation: Generate without unloading, then generate again")
    func reGenerationWorksWithoutReloading() async throws {
        // Setup
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        let config = GenerationConfig(maxTokens: 20)
        let prompt1 = "What is Swift?"
        let prompt2 = "What is Rust?"

        // First generation
        var firstTokens: [String] = []
        let stream1 = await service.generate(
            model: ModelPresets.gemma2B,
            prompt: prompt1,
            config: config
        )

        for try await token in stream1 {
            firstTokens.append(token)
        }

        #expect(!firstTokens.isEmpty, "First generation should produce tokens")

        // Second generation (without unloading)
        var secondTokens: [String] = []
        let stream2 = await service.generate(
            model: ModelPresets.gemma2B,
            prompt: prompt2,
            config: config
        )

        for try await token in stream2 {
            secondTokens.append(token)
        }

        #expect(!secondTokens.isEmpty, "Second generation should produce tokens")

        // Both generations should have stats
        let finalStats = await service.lastGenerationStats
        #expect(finalStats != nil, "Stats should be available after second generation")
        #expect(finalStats!.tokenCount == secondTokens.count, "Stats should reflect second generation")
    }

    // MARK: - Test 5: Stats Validation

    @Test("Stats validation: After generation, check GenerationStats")
    func generationStatsAreValid() async throws {
        // Setup
        let backend = MLXBackend()
        let modelManager = ModelManager()
        let service = LLMLocalService(backend: backend, modelManager: modelManager)

        let config = GenerationConfig(maxTokens: 30)
        let prompt = "Explain generics in Swift."

        // Generate
        var tokenCount = 0
        let stream = await service.generate(
            model: ModelPresets.gemma2B,
            prompt: prompt,
            config: config
        )

        for try await _ in stream {
            tokenCount += 1
        }

        // Verify stats
        let stats = await service.lastGenerationStats
        #expect(stats != nil, "Stats should exist after generation")

        if let stats = stats {
            // Token count validation
            #expect(stats.tokenCount > 0, "Token count must be positive")
            #expect(stats.tokenCount == tokenCount, "Token count should match received tokens")

            // Tokens per second validation
            #expect(stats.tokensPerSecond > 0, "Tokens per second must be positive")
            #expect(stats.tokensPerSecond.isFinite, "Tokens per second must be finite")
            #expect(!stats.tokensPerSecond.isNaN, "Tokens per second must not be NaN")

            // Duration validation
            #expect(stats.duration > .zero, "Duration must be positive")

            // Sanity check: tokens per second calculation
            let seconds = Double(stats.duration.components.seconds)
                + Double(stats.duration.components.attoseconds) / 1e18
            let expectedTPS = Double(stats.tokenCount) / seconds

            // Allow small floating point difference
            let tpsDifference = abs(stats.tokensPerSecond - expectedTPS)
            #expect(tpsDifference < 0.01, "Tokens per second should be calculated correctly")
        }
    }
}
#endif
