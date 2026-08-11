import Testing
@testable import LLMLocalClient

@Suite("ThinkTagParser")
struct ThinkTagParserTests {

    // MARK: - Basic Cases

    @Test("think タグ付きの標準的な出力を正しく分離する")
    func standardOutput() throws {
        var parser = ThinkTagParser()
        let results = parser.process("<think>reasoning</think>\n\nresponse")
            + parser.finalize()

        #expect(results == [
            .thinking("reasoning"),
            .text("\n\nresponse"),
        ])
    }

    @Test("think タグなしの出力は全てテキストになる")
    func noThinkTag() throws {
        var parser = ThinkTagParser()
        let results = parser.process("just plain text")
            + parser.finalize()

        #expect(results == [.text("just plain text")])
    }

    @Test("空の think ブロック")
    func emptyThinkBlock() throws {
        var parser = ThinkTagParser()
        let results = parser.process("<think></think>response")
            + parser.finalize()

        #expect(results == [.text("response")])
    }

    @Test("think 内に改行を含む")
    func thinkWithNewlines() throws {
        var parser = ThinkTagParser()
        let results = parser.process("<think>\nline1\nline2\n</think>\n\nresponse")
            + parser.finalize()

        #expect(results == [
            .thinking("\nline1\nline2\n"),
            .text("\n\nresponse"),
        ])
    }

    // MARK: - Chunked Input

    @Test("開始タグがチャンク境界でまたがる")
    func chunkedOpenTag() throws {
        var parser = ThinkTagParser()
        var results: [ThinkTagParser.ParsedChunk] = []

        results += parser.process("<thi")
        #expect(results.isEmpty) // still buffering: could be a tag or literal text

        results += parser.process("nk>")
        #expect(results.isEmpty) // tag consumed, now in the thinking state; the tag itself is not emitted

        results += parser.process("reasoning")
        results += parser.process("</think>")
        results += parser.process("response")
        results += parser.finalize()

        #expect(results == [
            .thinking("reasoning"),
            .text("response"),
        ])
    }

    @Test("終了タグがチャンク境界でまたがる")
    func chunkedCloseTag() throws {
        var parser = ThinkTagParser()
        var results: [ThinkTagParser.ParsedChunk] = []

        results += parser.process("<think>reasoning</th")
        results += parser.process("ink>response")
        results += parser.finalize()

        #expect(results == [
            .thinking("reasoning"),
            .text("response"),
        ])
    }

    @Test("1文字ずつ入力")
    func characterByCharacter() throws {
        let input = "<think>OK</think>Hi"
        var parser = ThinkTagParser()
        var results: [ThinkTagParser.ParsedChunk] = []

        for char in input {
            results += parser.process(String(char))
        }
        results += parser.finalize()

        // Joining first: character-at-a-time feeding splits the run into an unspecified number of
        // chunks, so only the thinking/text separation is pinned, not the chunk boundaries.
        let thinkingText = results.compactMap {
            if case .thinking(let t) = $0 { return t } else { return nil }
        }.joined()
        let responseText = results.compactMap {
            if case .text(let t) = $0 { return t } else { return nil }
        }.joined()

        #expect(thinkingText == "OK")
        #expect(responseText == "Hi")
    }

    // MARK: - Edge Cases

    @Test("未閉じの think タグ（モデル打ち切り）")
    func unclosedThinkTag() throws {
        var parser = ThinkTagParser()
        let results = parser.process("<think>incomplete reasoning")
            + parser.finalize()

        #expect(results == [
            .thinking("incomplete reasoning"),
        ])
    }

    @Test("< で始まるがタグではない")
    func lessThanButNotTag() throws {
        var parser = ThinkTagParser()
        var results: [ThinkTagParser.ParsedChunk] = []
        results += parser.process("<div>hello</div>")
        results += parser.finalize()

        #expect(results == [.text("<div>hello</div>")])
    }

    @Test("think タグ後に空文字列")
    func emptyResponseAfterThink() throws {
        var parser = ThinkTagParser()
        let results = parser.process("<think>reasoning</think>")
            + parser.finalize()

        #expect(results == [.thinking("reasoning")])
    }

    @Test("thinking 内に </thi で始まる偽の閉じタグ")
    func partialCloseTagInThinking() throws {
        var parser = ThinkTagParser()
        var results: [ThinkTagParser.ParsedChunk] = []
        results += parser.process("<think>text </thi then more</think>actual")
        results += parser.finalize()

        let thinkingText = results.compactMap {
            if case .thinking(let t) = $0 { return t } else { return nil }
        }.joined()
        let responseText = results.compactMap {
            if case .text(let t) = $0 { return t } else { return nil }
        }.joined()

        #expect(thinkingText == "text </thi then more")
        #expect(responseText == "actual")
    }

    @Test("複数チャンクにまたがる終了タグの部分一致")
    func partialCloseTagAcrossChunks() throws {
        var parser = ThinkTagParser()
        var results: [ThinkTagParser.ParsedChunk] = []

        results += parser.process("<think>content</")
        results += parser.process("think>response")
        results += parser.finalize()

        let thinkingText = results.compactMap {
            if case .thinking(let t) = $0 { return t } else { return nil }
        }.joined()
        let responseText = results.compactMap {
            if case .text(let t) = $0 { return t } else { return nil }
        }.joined()

        #expect(thinkingText == "content")
        #expect(responseText == "response")
    }
}
