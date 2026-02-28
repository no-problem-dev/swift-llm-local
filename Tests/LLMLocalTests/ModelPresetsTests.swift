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

    @Test("all presets have a profile")
    func allPresetsHaveProfile() {
        for preset in ModelPresets.all {
            #expect(preset.profile != nil, "Model \(preset.id) has no profile")
        }
    }

    @Test("all profiles have non-empty summary")
    func allProfilesHaveNonEmptySummary() {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(!profile.summary.isEmpty, "Model \(preset.id) profile has empty summary")
        }
    }

    @Test("all profiles have non-empty modelFamily")
    func allProfilesHaveModelFamily() {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(!profile.modelFamily.isEmpty, "Model \(preset.id) profile has empty modelFamily")
        }
    }

    @Test("all profiles have text modality")
    func allProfilesHaveTextModality() {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(
                profile.modalities.contains(.text),
                "Model \(preset.id) profile missing text modality"
            )
        }
    }

    @Test("all local profiles have quantization info")
    func allLocalProfilesHaveQuantization() {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(
                profile.quantization != nil,
                "Model \(preset.id) profile missing quantization"
            )
        }
    }

    @Test("all local profiles have inference speed")
    func allLocalProfilesHaveInferenceSpeed() {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(
                profile.inferenceSpeed != nil,
                "Model \(preset.id) profile missing inferenceSpeed"
            )
        }
    }
}
