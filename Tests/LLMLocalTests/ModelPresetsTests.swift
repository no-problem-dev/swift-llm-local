import Testing
import LLMLocalClient
@testable import LLMLocal

@Suite("ModelPresets")
struct ModelPresetsTests {

    @Test("gemma2B has correct ID")
    func gemma2BHasCorrectID() {
        // Arrange & Act
        let preset = ModelPresets.gemma2B

        // Assert
        #expect(preset.id == "gemma-2-2b-it-4bit")
    }

    @Test("gemma2B has HuggingFace base source")
    func gemma2BHasHuggingFaceBase() {
        // Arrange & Act
        let preset = ModelPresets.gemma2B

        // Assert
        #expect(preset.base == .huggingFace(id: "mlx-community/gemma-2-2b-it-4bit"))
    }

    @Test("gemma2B has no adapter")
    func gemma2BHasNoAdapter() {
        // Arrange & Act
        let preset = ModelPresets.gemma2B

        // Assert
        #expect(preset.adapter == nil)
    }

    @Test("gemma2B has correct context length")
    func gemma2BHasCorrectContextLength() {
        // Arrange & Act
        let preset = ModelPresets.gemma2B

        // Assert
        #expect(preset.contextLength == 8192)
    }

    @Test("gemma2B has correct display name")
    func gemma2BHasCorrectDisplayName() {
        // Arrange & Act
        let preset = ModelPresets.gemma2B

        // Assert
        #expect(preset.displayName == "Gemma 2 2B")
    }

    @Test("gemma2B has non-empty description")
    func gemma2BHasNonEmptyDescription() {
        // Arrange & Act
        let preset = ModelPresets.gemma2B

        // Assert
        #expect(!preset.description.isEmpty)
    }
}
