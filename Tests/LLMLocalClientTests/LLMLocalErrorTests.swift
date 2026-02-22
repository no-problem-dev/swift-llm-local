import Testing
@testable import LLMLocalClient

@Suite("LLMLocalError")
struct LLMLocalErrorTests {

    // MARK: - Error case creation and associated values

    @Test("downloadFailed preserves modelId and reason")
    func downloadFailed() {
        let error = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "Network timeout")
        if case .downloadFailed(let modelId, let reason) = error {
            #expect(modelId == "llama-3")
            #expect(reason == "Network timeout")
        } else {
            Issue.record("Expected downloadFailed case")
        }
    }

    @Test("loadFailed preserves modelId and reason")
    func loadFailed() {
        let error = LLMLocalError.loadFailed(modelId: "mistral-7b", reason: "Corrupted weights")
        if case .loadFailed(let modelId, let reason) = error {
            #expect(modelId == "mistral-7b")
            #expect(reason == "Corrupted weights")
        } else {
            Issue.record("Expected loadFailed case")
        }
    }

    @Test("insufficientMemory preserves required and available")
    func insufficientMemory() {
        let error = LLMLocalError.insufficientMemory(required: 8_000_000_000, available: 4_000_000_000)
        if case .insufficientMemory(let required, let available) = error {
            #expect(required == 8_000_000_000)
            #expect(available == 4_000_000_000)
        } else {
            Issue.record("Expected insufficientMemory case")
        }
    }

    @Test("insufficientStorage preserves required and available")
    func insufficientStorage() {
        let error = LLMLocalError.insufficientStorage(required: 20_000_000_000, available: 5_000_000_000)
        if case .insufficientStorage(let required, let available) = error {
            #expect(required == 20_000_000_000)
            #expect(available == 5_000_000_000)
        } else {
            Issue.record("Expected insufficientStorage case")
        }
    }

    @Test("modelNotLoaded case is created")
    func modelNotLoaded() {
        let error = LLMLocalError.modelNotLoaded
        #expect(error == .modelNotLoaded)
    }

    @Test("loadInProgress case is created")
    func loadInProgress() {
        let error = LLMLocalError.loadInProgress
        #expect(error == .loadInProgress)
    }

    @Test("cancelled case is created")
    func cancelled() {
        let error = LLMLocalError.cancelled
        #expect(error == .cancelled)
    }

    @Test("adapterMergeFailed preserves reason")
    func adapterMergeFailed() {
        let error = LLMLocalError.adapterMergeFailed(reason: "Dimension mismatch")
        if case .adapterMergeFailed(let reason) = error {
            #expect(reason == "Dimension mismatch")
        } else {
            Issue.record("Expected adapterMergeFailed case")
        }
    }

    @Test("unsupportedModelFormat preserves format string")
    func unsupportedModelFormat() {
        let error = LLMLocalError.unsupportedModelFormat("ONNX")
        if case .unsupportedModelFormat(let format) = error {
            #expect(format == "ONNX")
        } else {
            Issue.record("Expected unsupportedModelFormat case")
        }
    }

    // MARK: - Error protocol conformance

    @Test("conforms to Error protocol")
    func conformsToError() {
        let error: any Error = LLMLocalError.modelNotLoaded
        #expect(error is LLMLocalError)
    }

    // MARK: - Equatable conformance

    @Test("same cases with same values are equal")
    func equalCases() {
        let a = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "timeout")
        let b = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "timeout")
        #expect(a == b)
    }

    @Test("same cases with different values are not equal")
    func differentValues() {
        let a = LLMLocalError.downloadFailed(modelId: "llama-3", reason: "timeout")
        let b = LLMLocalError.downloadFailed(modelId: "mistral-7b", reason: "timeout")
        #expect(a != b)
    }

    @Test("different cases are not equal")
    func differentCases() {
        let a = LLMLocalError.modelNotLoaded
        let b = LLMLocalError.loadInProgress
        #expect(a != b)
    }

    @Test("simple cases without associated values are equal")
    func simpleCasesEqual() {
        #expect(LLMLocalError.cancelled == LLMLocalError.cancelled)
        #expect(LLMLocalError.modelNotLoaded == LLMLocalError.modelNotLoaded)
        #expect(LLMLocalError.loadInProgress == LLMLocalError.loadInProgress)
    }

    // MARK: - Sendable (compile-time check)

    @Test("error is Sendable")
    func sendableCheck() async {
        let error = LLMLocalError.modelNotLoaded
        let result = await sendAcrossBoundary(error)
        #expect(result == .modelNotLoaded)
    }
}

// Helper to verify Sendable conformance at compile time.
private func sendAcrossBoundary<T: Sendable>(_ value: T) async -> T {
    value
}
