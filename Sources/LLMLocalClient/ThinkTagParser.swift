/// Splits a streaming response into the model's reasoning span and the answer meant for the reader.
///
/// Reasoning models (Qwen3 and relatives) prefix their answer with a `<think>…</think>` span. Those
/// tokens are generated like any other — they cost time and count toward usage — but showing them
/// is almost never what the reader wants. This state machine separates the two as fragments arrive,
/// so the answer can be rendered live instead of waiting for the closing tag. To suppress the
/// reasoning tokens altogether rather than hide them, set ``GenerationConfig/enableThinking`` to
/// `false`.
///
/// ## Chunk boundaries
///
/// A tag can be split across fragments, so the parser holds back any tail that could still turn out
/// to be the start of a tag. Feeding `"<thi"` emits nothing; the following `"nk>"` completes the
/// open tag and emits nothing either. While inside the reasoning span, a tail matching a prefix of
/// the closing tag — `"</thi"` — is withheld until the next fragment resolves it, which is why a
/// literal `"</thi"` in the middle of the reasoning text is eventually emitted as reasoning rather
/// than swallowed. Nothing is ever emitted twice, and empty fragments are never emitted.
///
/// ## Where detection can miss
///
/// The opening tag is only recognized at the very start of the stream. If the model emits anything
/// before it — even a newline — the parser decides there is no think span, switches to text for the
/// rest of the stream, and passes the whole `<think>` block through as visible answer text. It also
/// stops looking after the first closing tag, so a second reasoning span later in the same response
/// is passed through as text.
///
/// ## End of stream
///
/// ``finalize()`` flushes whatever is still held back, and the state at that moment decides how:
/// an unterminated reasoning span is emitted as reasoning, so a response cut short mid-thought
/// never leaks its reasoning into the answer, while a half-written opening tag is emitted as text.
/// Always call it; a response that ends inside a held-back tail loses that text otherwise. The
/// parser keeps its state afterwards, so use a fresh instance per response.
///
/// ## Example
///
/// ```swift
/// var parser = ThinkTagParser()
/// for try await token in stream {
///     for chunk in parser.process(token) {
///         switch chunk {
///         case .thinking(let text): handleThinking(text)
///         case .text(let text):     handleText(text)
///         }
///     }
/// }
/// for chunk in parser.finalize() { ... }
/// ```
public struct ThinkTagParser: Sendable {

    /// One classified piece of the stream, with the tags themselves already removed.
    public enum ParsedChunk: Sendable, Equatable {
        /// Reasoning content from inside the think span.
        case thinking(String)
        /// Answer text, either after the closing tag or from a response that had no think span.
        case text(String)
    }

    private enum State: Sendable {
        /// Nothing decided yet: still checking whether the response opens with a think tag.
        case initial
        /// Inside the think span, watching for the closing tag.
        case thinking
        /// Past the think span; everything from here is answer text.
        case text
    }

    private var state: State = .initial
    private var buffer: String = ""

    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    public init() {}

    /// Feeds the next fragment of the stream and returns whatever can now be classified.
    ///
    /// An empty result is normal and means the fragment is being held back as a possible tag, not
    /// that anything was lost. One fragment can produce several chunks when a think span closes
    /// inside it.
    ///
    /// - Parameter chunk: Next fragment as received from the backend.
    public mutating func process(_ chunk: String) -> [ParsedChunk] {
        var results: [ParsedChunk] = []
        buffer += chunk

        switch state {
        case .initial:
            processInitial(&results)
        case .thinking:
            processThinking(&results)
        case .text:
            // Past the closing tag: no further tag detection, everything through as text.
            let text = buffer
            buffer = ""
            if !text.isEmpty {
                results.append(.text(text))
            }
        }

        return results
    }

    /// Flushes text held back as a possible tag; call it once the stream has ended.
    ///
    /// Text withheld mid-tag is only released here, so skipping this call silently truncates
    /// responses that end on a `<` or a partial closing tag. An unterminated think span is flushed
    /// as reasoning, never as answer text.
    public mutating func finalize() -> [ParsedChunk] {
        guard !buffer.isEmpty else { return [] }

        let remaining = buffer
        buffer = ""

        switch state {
        case .initial:
            // The open tag never completed, so what was held back is ordinary text.
            return [.text(remaining)]
        case .thinking:
            // Think span never closed (generation was cut short) — keep it out of the answer.
            return [.thinking(remaining)]
        case .text:
            return [.text(remaining)]
        }
    }

    // MARK: - Private

    private mutating func processInitial(_ results: inout [ParsedChunk]) {
        // The open tag is only accepted at the very start of the stream.
        let openTag = Self.openTag

        if buffer.hasPrefix(openTag) {
            // Open tag complete: drop it and start collecting reasoning.
            buffer.removeFirst(openTag.count)
            state = .thinking
            // The same fragment may already contain reasoning, and even the closing tag.
            if !buffer.isEmpty {
                processThinking(&results)
            }
        } else if openTag.hasPrefix(buffer) {
            // Still a possible open tag ("<thi") — hold it back for the next fragment.
            return
        } else {
            // Cannot become an open tag, so this response has no think span at all.
            state = .text
            let text = buffer
            buffer = ""
            if !text.isEmpty {
                results.append(.text(text))
            }
        }
    }

    private mutating func processThinking(_ results: inout [ParsedChunk]) {
        let closeTag = Self.closeTag

        // Look for the closing tag; the first hit ends the span for the rest of the stream.
        while let range = buffer.range(of: closeTag) {
            // Everything before the tag is reasoning.
            let thinkingContent = String(buffer[buffer.startIndex..<range.lowerBound])
            if !thinkingContent.isEmpty {
                results.append(.thinking(thinkingContent))
            }

            // Drop the tag itself and switch over to answer text.
            buffer = String(buffer[range.upperBound...])
            state = .text

            // Anything after the tag in this same fragment is already answer text.
            if !buffer.isEmpty {
                results.append(.text(buffer))
                buffer = ""
            }
            return
        }

        // No closing tag yet: the tail may still be the start of one, split across fragments.
        // For "content</thi", "</thi" is withheld and only "content" is emitted.
        let holdBack = partialCloseTagSuffix()
        if holdBack > 0 {
            let emitEnd = buffer.index(buffer.endIndex, offsetBy: -holdBack)
            let thinkingContent = String(buffer[buffer.startIndex..<emitEnd])
            buffer = String(buffer[emitEnd...])
            if !thinkingContent.isEmpty {
                results.append(.thinking(thinkingContent))
            }
        } else {
            // Nothing tag-like at the tail, so the whole buffer is reasoning.
            let thinkingContent = buffer
            buffer = ""
            if !thinkingContent.isEmpty {
                results.append(.thinking(thinkingContent))
            }
        }
    }

    /// Length of the buffer's tail that could still grow into the closing tag.
    private func partialCloseTagSuffix() -> Int {
        let closeTag = Self.closeTag
        // Longest match wins, from a bare "<" up to one character short of the whole tag.
        let maxCheck = min(buffer.count, closeTag.count - 1)
        for length in stride(from: maxCheck, through: 1, by: -1) {
            let suffix = String(buffer.suffix(length))
            let prefix = String(closeTag.prefix(length))
            if suffix == prefix {
                return length
            }
        }
        return 0
    }
}
