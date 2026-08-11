import Foundation
import Testing
@testable import LLMLocalClient

@Suite("LLMLocalError")
struct LLMLocalErrorTests {

    // MARK: - Error case creation and associated values

    @Test("downloadFailed preserves modelId and reason")
    func downloadFailed() throws {
        let error = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "Network timeout")
        if case .downloadFailed(let modelId, let reason) = error {
            #expect(modelId == "llama-3")
            #expect(reason == "Network timeout")
        } else {
            Issue.record("Expected downloadFailed case")
        }
    }

    @Test("loadFailed preserves modelId and reason")
    func loadFailed() throws {
        let error = LLMLocalError.loadFailed(modelId: "mistral-7b", reason: "Corrupted weights")
        if case .loadFailed(let modelId, let reason) = error {
            #expect(modelId == "mistral-7b")
            #expect(reason == "Corrupted weights")
        } else {
            Issue.record("Expected loadFailed case")
        }
    }

    @Test("modelNotLoaded case is created")
    func modelNotLoaded() throws {
        let error = LLMLocalError.modelNotLoaded
        #expect(error == .modelNotLoaded)
    }

    @Test("loadInProgress case is created")
    func loadInProgress() throws {
        let error = LLMLocalError.loadInProgress
        #expect(error == .loadInProgress)
    }

    @Test("cancelled case is created")
    func cancelled() throws {
        let error = LLMLocalError.cancelled
        #expect(error == .cancelled)
    }

    @Test("adapterMergeFailed preserves reason")
    func adapterMergeFailed() throws {
        let error = LLMLocalError.adapterMergeFailed(reason: "Dimension mismatch")
        if case .adapterMergeFailed(let reason) = error {
            #expect(reason == "Dimension mismatch")
        } else {
            Issue.record("Expected adapterMergeFailed case")
        }
    }

    @Test("toolCallsUnsupported preserves modelId")
    func toolCallsUnsupported() throws {
        let error = LLMLocalError.toolCallsUnsupported(modelId: "gemma-2b")
        if case .toolCallsUnsupported(let modelId) = error {
            #expect(modelId == "gemma-2b")
        } else {
            Issue.record("Expected toolCallsUnsupported case")
        }
    }

    // MARK: - Error protocol conformance

    @Test("conforms to Error protocol")
    func conformsToError() throws {
        let error: any Error = LLMLocalError.modelNotLoaded
        #expect(error is LLMLocalError)
    }

    // MARK: - Equatable conformance

    @Test("same cases with same values are equal")
    func equalCases() throws {
        let a = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "timeout")
        let b = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "timeout")
        #expect(a == b)
    }

    @Test("same cases with different values are not equal")
    func differentValues() throws {
        let a = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "timeout")
        let b = LLMLocalError.downloadFailed(modelId: "mistral-7b", reason: "timeout")
        #expect(a != b)
    }

    @Test("different cases are not equal")
    func differentCases() throws {
        let a = LLMLocalError.modelNotLoaded
        let b = LLMLocalError.loadInProgress
        #expect(a != b)
    }

    @Test("simple cases without associated values are equal")
    func simpleCasesEqual() throws {
        #expect(LLMLocalError.cancelled == LLMLocalError.cancelled)
        #expect(LLMLocalError.modelNotLoaded == LLMLocalError.modelNotLoaded)
        #expect(LLMLocalError.loadInProgress == LLMLocalError.loadInProgress)
    }

    // MARK: - Sendable (compile-time check)

    @Test("error is Sendable")
    func sendableCheck() async throws {
        let error = LLMLocalError.modelNotLoaded
        let result = await sendAcrossBoundary(error)
        #expect(result == .modelNotLoaded)
    }
}

// MARK: - errorDescription

/// One value per case, so the descriptions below can be checked exhaustively.
///
/// `describe(_:)` switches over this enum without a `default`, so adding a case to
/// `LLMLocalError` breaks compilation here until its description is covered too.
private let everyCase: [LLMLocalError] = [
    .downloadFailed(modelId: "llama-3", reason: "Network timeout"),
    .loadFailed(modelId: "mistral-7b", reason: "Corrupted weights"),
    .modelNotLoaded,
    .loadInProgress,
    .cancelled,
    .adapterMergeFailed(reason: "Dimension mismatch"),
    .toolCallsUnsupported(modelId: "gemma-2b"),
    .registryUnreadable(reason: "Decoding failed for key 'registry': truncated JSON"),
    .storageUnreadable(
        path: "/Library/Application Support/swift-llm-local/models/mlx-community/Qwen3-4B",
        reason: "You don't have permission to view it."
    ),
    .memoryUnreadable(reason: "host_page_size failed with kern_return_t 5."),
]

/// Exhaustive re-statement of the expected copy, used to prove `everyCase` covers the enum.
private func expectedDescription(_ error: LLMLocalError) -> String {
    switch error {
    case .downloadFailed(let modelId, let reason):
        "Failed to download model '\(modelId)': \(reason)"
    case .loadFailed(let modelId, let reason):
        "Failed to load model '\(modelId)': \(reason)"
    case .modelNotLoaded:
        "No model is loaded."
    case .loadInProgress:
        "A model load is already in progress."
    case .cancelled:
        "The operation was cancelled."
    case .adapterMergeFailed(let reason):
        "Failed to merge the adapter: \(reason)"
    case .toolCallsUnsupported(let modelId):
        "Model '\(modelId)' does not support tool calls."
    case .registryUnreadable(let reason):
        "The registry of downloaded items could not be read: \(reason)"
    case .storageUnreadable(let path, let reason):
        "The model storage at '\(path)' could not be read: \(reason)"
    case .memoryUnreadable(let reason):
        "The device's memory could not be measured: \(reason)"
    }
}

@Suite("LLMLocalError errorDescription")
struct LLMLocalErrorDescriptionTests {

    @Test("every case describes itself in English")
    func everyCaseIsEnglish() throws {
        for error in everyCase {
            #expect(error.errorDescription == expectedDescription(error))
        }
    }

    /// The descriptions reach consumers' error handling, so they must not carry Japanese copy that
    /// an English-language app would surface verbatim.
    @Test("no description contains Japanese characters")
    func noJapaneseInDescriptions() throws {
        // Hiragana, katakana, CJK ideographs, and the CJK punctuation used in the old copy.
        let japanese = CharacterSet(charactersIn: "\u{3040}"..."\u{30FF}")
            .union(CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}"))
            .union(CharacterSet(charactersIn: "\u{FF00}"..."\u{FFEF}"))

        for error in everyCase {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
            #expect(
                description.rangeOfCharacter(from: japanese) == nil,
                "Japanese copy leaked into errorDescription: \(description)"
            )
        }
    }

    @Test("localizedDescription keeps the associated values")
    func localizedDescriptionKeepsValues() throws {
        let error = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "Network timeout")
        #expect(error.localizedDescription.contains("llama-3"))
        #expect(error.localizedDescription.contains("Network timeout"))
    }
}

// Helper to verify Sendable conformance at compile time.
private func sendAcrossBoundary<T: Sendable>(_ value: T) async -> T {
    value
}
