import Testing
import LLMLocalClient
@testable import LLMLocal

@Suite("ModelPresets")
struct ModelPresetsTests {

    @Test("all presets have unique IDs")
    func allPresetsHaveUniqueIDs() throws {
        let ids = ModelPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("all presets have non-zero memory estimate")
    func allPresetsHaveNonZeroMemory() throws {
        for preset in ModelPresets.all {
            #expect(preset.estimatedMemoryBytes > 0, "Model \(preset.id) has zero memory")
        }
    }

    @Test("all presets have non-empty description")
    func allPresetsHaveNonEmptyDescription() throws {
        for preset in ModelPresets.all {
            #expect(!preset.description.isEmpty, "Model \(preset.id) has empty description")
        }
    }

    @Test("all array is sorted by memory size")
    func allArrayIsSortedByMemory() throws {
        let memories = ModelPresets.all.map(\.estimatedMemoryBytes)
        #expect(memories == memories.sorted())
    }

    @Test("contains expected model count")
    func containsExpectedModelCount() throws {
        #expect(ModelPresets.all.count >= 30)
    }

    @Test("all presets have a profile")
    func allPresetsHaveProfile() throws {
        for preset in ModelPresets.all {
            #expect(preset.profile != nil, "Model \(preset.id) has no profile")
        }
    }

    @Test("all profiles have non-empty summary")
    func allProfilesHaveNonEmptySummary() throws {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(!profile.summary.isEmpty, "Model \(preset.id) profile has empty summary")
        }
    }

    @Test("all profiles have non-empty modelFamily")
    func allProfilesHaveModelFamily() throws {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(!profile.modelFamily.isEmpty, "Model \(preset.id) profile has empty modelFamily")
        }
    }

    @Test("all profiles have text modality")
    func allProfilesHaveTextModality() throws {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(
                profile.modalities.contains(.text),
                "Model \(preset.id) profile missing text modality"
            )
        }
    }

    @Test("all local profiles have quantization info")
    func allLocalProfilesHaveQuantization() throws {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(
                profile.quantization != nil,
                "Model \(preset.id) profile missing quantization"
            )
        }
    }

    @Test("all local profiles have inference speed")
    func allLocalProfilesHaveInferenceSpeed() throws {
        for preset in ModelPresets.all {
            guard let profile = preset.profile else { continue }
            #expect(
                profile.inferenceSpeed != nil,
                "Model \(preset.id) profile missing inferenceSpeed"
            )
        }
    }

    // MARK: - Recommended Generation invariants
    //
    // Every preset must carry an explicit family-specific generation config instead of falling
    // back to `GenerationConfig.default`, which turns thinking on and uses generic sampling.
    // When a preset loses its explicit config, a large model such as Qwen keeps running in
    // thinking mode unnoticed and becomes extremely slow.

    /// Allow list of reasoning-first model IDs, the only ones for which thinking mode is correct.
    /// Every other on-device model defaults to thinking off, because agent use pays for the
    /// thinking tokens in latency without gaining anything.
    static let reasoningModelIDs: Set<String> = [
        "deepseek-r1-distill-qwen-1.5b-4bit",
        "deepseek-r1-distill-qwen-7b-4bit",
        "deepseek-r1-distill-qwen-14b-4bit",
        "gpt-oss-20b-mxfp4-q8",
    ]

    @Test("every preset has an explicit recommendedGeneration (never .default)")
    func everyPresetHasExplicitRecommendedGeneration() throws {
        for preset in ModelPresets.all {
            #expect(
                preset.recommendedGeneration != .default,
                "Model \(preset.id) falls back to GenerationConfig.default (thinking ON / generic sampling). Assign a family preset."
            )
        }
    }

    @Test("non-reasoning presets disable thinking; reasoning presets keep it on")
    func thinkingModeMatchesModelKind() throws {
        for preset in ModelPresets.all {
            let expectedThinking = Self.reasoningModelIDs.contains(preset.id)
            #expect(
                preset.recommendedGeneration.enableThinking == expectedThinking,
                "Model \(preset.id) enableThinking=\(preset.recommendedGeneration.enableThinking), expected \(expectedThinking)"
            )
        }
    }
}
