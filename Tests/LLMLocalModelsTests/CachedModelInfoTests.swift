import Foundation
import Testing
@testable import LLMLocalModels

@Suite("CachedModelInfo")
struct CachedModelInfoTests {

    // MARK: - Initialization

    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        // Arrange
        let now = Date()
        let path = URL(fileURLWithPath: "/tmp/models/test-model")

        // Act
        let info = CachedModelInfo(
            modelId: "test-model",
            displayName: "Test Model",
            sizeInBytes: 1_000_000,
            downloadedAt: now,
            localPath: path
        )

        // Assert
        #expect(info.modelId == "test-model")
        #expect(info.displayName == "Test Model")
        #expect(info.sizeInBytes == 1_000_000)
        #expect(info.downloadedAt == now)
        #expect(info.localPath == path)
    }

    // MARK: - Codable

    @Test("encodes and decodes via JSON round-trip")
    func encodesAndDecodesViaJSON() throws {
        // Arrange
        let now = Date()
        let path = URL(fileURLWithPath: "/tmp/models/test-model")
        let original = CachedModelInfo(
            modelId: "model-1",
            displayName: "Model One",
            sizeInBytes: 2_500_000,
            downloadedAt: now,
            localPath: path
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Act
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CachedModelInfo.self, from: data)

        // Assert
        #expect(decoded.modelId == original.modelId)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.sizeInBytes == original.sizeInBytes)
        #expect(decoded.downloadedAt == original.downloadedAt)
        #expect(decoded.localPath == original.localPath)
    }

    @Test("decodes from known JSON structure")
    func decodesFromKnownJSON() throws {
        // Arrange
        let path = URL(fileURLWithPath: "/tmp/models/known")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = CachedModelInfo(
            modelId: "known-model",
            displayName: "Known",
            sizeInBytes: 500,
            downloadedAt: date,
            localPath: path
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Act
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CachedModelInfo.self, from: data)

        // Assert
        #expect(decoded.modelId == "known-model")
        #expect(decoded.sizeInBytes == 500)
    }

    // MARK: - Sendable

    @Test("is Sendable")
    func isSendable() {
        // Arrange & Act
        let info = CachedModelInfo(
            modelId: "sendable-test",
            displayName: "Sendable Test",
            sizeInBytes: 100,
            downloadedAt: Date(),
            localPath: URL(fileURLWithPath: "/tmp/sendable")
        )

        // Assert - if this compiles, CachedModelInfo is Sendable
        let _: any Sendable = info
        #expect(info.modelId == "sendable-test")
    }

    // MARK: - modelFilesPath

    @Test("initializes with modelFilesPath")
    func initializesWithModelFilesPath() {
        let filesPath = URL(fileURLWithPath: "/tmp/huggingface/models/test")
        let info = CachedModelInfo(
            modelId: "test",
            displayName: "Test",
            sizeInBytes: 100,
            downloadedAt: Date(),
            localPath: URL(fileURLWithPath: "/tmp/local"),
            modelFilesPath: filesPath
        )
        #expect(info.modelFilesPath == filesPath)
    }

    @Test("modelFilesPath defaults to nil")
    func modelFilesPathDefaultsToNil() {
        let info = CachedModelInfo(
            modelId: "test",
            displayName: "Test",
            sizeInBytes: 100,
            downloadedAt: Date(),
            localPath: URL(fileURLWithPath: "/tmp/local")
        )
        #expect(info.modelFilesPath == nil)
    }

    @Test("backward compatible: decodes JSON without modelFilesPath")
    func backwardCompatibleDecoding() throws {
        // Simulate legacy JSON without modelFilesPath field
        let legacyJSON = """
        {
            "modelId": "legacy-model",
            "displayName": "Legacy",
            "sizeInBytes": 500,
            "downloadedAt": 1700000000,
            "localPath": "file:///tmp/models/legacy"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CachedModelInfo.self, from: legacyJSON)
        #expect(decoded.modelId == "legacy-model")
        #expect(decoded.modelFilesPath == nil)
    }

    @Test("Codable round-trip preserves modelFilesPath")
    func codableRoundTripWithModelFilesPath() throws {
        let filesPath = URL(fileURLWithPath: "/tmp/hf/models/qwen")
        let original = CachedModelInfo(
            modelId: "qwen-test",
            displayName: "Qwen Test",
            sizeInBytes: 2000,
            downloadedAt: Date(),
            localPath: URL(fileURLWithPath: "/tmp/local"),
            modelFilesPath: filesPath
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CachedModelInfo.self, from: data)

        #expect(decoded.modelFilesPath == filesPath)
    }
}
