import Testing
import LLMLocalClient
@testable import LLMLocal

@Suite("ModelPresets")
struct ModelPresetsTests {

    @Test("all presets have unique IDs")
    func allPresetsHaveUniqueIDs() {
        let ids = ModelPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("all presets have non-zero memory estimate")
    func allPresetsHaveNonZeroMemory() {
        for preset in ModelPresets.all {
            #expect(preset.estimatedMemoryBytes > 0, "Model \(preset.id) has zero memory")
        }
    }

    @Test("all presets have non-empty description")
    func allPresetsHaveNonEmptyDescription() {
        for preset in ModelPresets.all {
            #expect(!preset.description.isEmpty, "Model \(preset.id) has empty description")
        }
    }

    @Test("all array is sorted by memory size")
    func allArrayIsSortedByMemory() {
        let memories = ModelPresets.all.map(\.estimatedMemoryBytes)
        #expect(memories == memories.sorted())
    }

    @Test("contains expected model count")
    func containsExpectedModelCount() {
        #expect(ModelPresets.all.count >= 30)
    }
}
