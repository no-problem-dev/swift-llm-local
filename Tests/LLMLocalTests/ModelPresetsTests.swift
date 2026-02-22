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

    // MARK: - Qwen3 4B Instruct 2507

    @Test("qwen3_4B has correct ID")
    func qwen3_4BHasCorrectID() {
        let preset = ModelPresets.qwen3_4B
        #expect(preset.id == "qwen3-4b-instruct-2507-4bit")
    }

    @Test("qwen3_4B has HuggingFace base source")
    func qwen3_4BHasHuggingFaceBase() {
        let preset = ModelPresets.qwen3_4B
        #expect(preset.base == .huggingFace(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit"))
    }

    @Test("qwen3_4B has no adapter")
    func qwen3_4BHasNoAdapter() {
        let preset = ModelPresets.qwen3_4B
        #expect(preset.adapter == nil)
    }

    @Test("qwen3_4B has correct context length")
    func qwen3_4BHasCorrectContextLength() {
        let preset = ModelPresets.qwen3_4B
        #expect(preset.contextLength == 4096)
    }

    @Test("qwen3_4B has correct display name")
    func qwen3_4BHasCorrectDisplayName() {
        let preset = ModelPresets.qwen3_4B
        #expect(preset.displayName == "Qwen3 4B Instruct 2507")
    }

    // MARK: - Qwen3 4B Japanese Fine-tuned

    @Test("qwen3_4B_ja has correct ID")
    func qwen3_4B_jaHasCorrectID() {
        let preset = ModelPresets.qwen3_4B_ja
        #expect(preset.id == "qwen3-4b-ja-4bit")
    }

    @Test("qwen3_4B_ja has HuggingFace base source")
    func qwen3_4B_jaHasHuggingFaceBase() {
        let preset = ModelPresets.qwen3_4B_ja
        #expect(preset.base == .huggingFace(id: "taniguchi-kyoichi/Qwen3-4B-Instruct-2507-ja-4bit"))
    }

    @Test("qwen3_4B_ja has no adapter (fused model)")
    func qwen3_4B_jaHasNoAdapter() {
        let preset = ModelPresets.qwen3_4B_ja
        #expect(preset.adapter == nil)
    }

    @Test("qwen3_4B_ja has correct context length")
    func qwen3_4B_jaHasCorrectContextLength() {
        let preset = ModelPresets.qwen3_4B_ja
        #expect(preset.contextLength == 4096)
    }

    @Test("qwen3_4B_ja has correct display name")
    func qwen3_4B_jaHasCorrectDisplayName() {
        let preset = ModelPresets.qwen3_4B_ja
        #expect(preset.displayName == "Qwen3 4B 日本語")
    }

    @Test("qwen3_4B_ja has non-empty description")
    func qwen3_4B_jaHasNonEmptyDescription() {
        let preset = ModelPresets.qwen3_4B_ja
        #expect(!preset.description.isEmpty)
    }
}
