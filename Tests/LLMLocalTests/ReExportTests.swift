import Testing
import LLMLocal

/// Verifies that `import LLMLocal` re-exports all sub-module types.
@Suite("Re-export")
struct ReExportTests {

    @Test("LLMLocalClient types are accessible via import LLMLocal")
    func clientTypesAccessible() {
        // ModelSpec
        let spec = ModelSpec(
            id: "test",
            base: .huggingFace(id: "test/model"),
            contextLength: 4096,
            displayName: "Test",
            description: "Test model"
        )
        #expect(spec.id == "test")

        // GenerationConfig
        let config = GenerationConfig()
        #expect(config.maxTokens == 1024)

        // GenerationStats
        let stats = GenerationStats(
            tokenCount: 10,
            tokensPerSecond: 5.0,
            duration: .seconds(2)
        )
        #expect(stats.tokenCount == 10)

        // LLMLocalError
        let error = LLMLocalError.modelNotLoaded
        #expect(error == .modelNotLoaded)

        // ModelSource
        let source = ModelSource.huggingFace(id: "test")
        #expect(source == .huggingFace(id: "test"))
    }

    @Test("LLMLocalModels types are accessible via import LLMLocal")
    func modelsTypesAccessible() async {
        // ModelManager
        let manager = ModelManager()
        let models = await manager.cachedModels()
        #expect(models.isEmpty)
    }

    @Test("LLMLocal-specific types are accessible")
    func localSpecificTypesAccessible() {
        // LLMLocalService - verify the type exists and is accessible
        let serviceType = LLMLocalService.self
        #expect(serviceType == LLMLocalService.self)

        // ModelPresets
        let preset = ModelPresets.gemma2B
        #expect(!preset.id.isEmpty)
    }
}
