import Testing
@testable import LLMLocalMLX

// MARK: - PromptCacheStore Prefix Logic

@Suite("PromptCacheStore commonPrefixLength")
struct PromptCacheStoreCommonPrefixTests {

    @Test("空配列の共通接頭辞は 0")
    func emptyArrays() throws {
        #expect(PromptCacheStore.commonPrefixLength([], []) == 0)
        #expect(PromptCacheStore.commonPrefixLength([1, 2, 3], []) == 0)
        #expect(PromptCacheStore.commonPrefixLength([], [1, 2, 3]) == 0)
    }

    @Test("完全一致は短い方の長さ")
    func identicalArrays() throws {
        #expect(PromptCacheStore.commonPrefixLength([1, 2, 3], [1, 2, 3]) == 3)
    }

    @Test("接頭辞が一致し片方が伸びている（エージェントの追記ケース）")
    func appendedSuffix() throws {
        let prev = [10, 20, 30]
        let next = [10, 20, 30, 40, 50]
        #expect(PromptCacheStore.commonPrefixLength(prev, next) == 3)
    }

    @Test("途中で分岐する場合は分岐位置まで")
    func divergence() throws {
        #expect(PromptCacheStore.commonPrefixLength([1, 2, 3, 4], [1, 2, 9, 4]) == 2)
    }

    @Test("先頭から不一致なら 0")
    func divergeAtStart() throws {
        #expect(PromptCacheStore.commonPrefixLength([1, 2, 3], [9, 2, 3]) == 0)
    }
}
