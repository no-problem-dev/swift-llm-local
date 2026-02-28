/// ストリーミングトークンから `<think>...</think>` タグを検出・分離するステートマシン。
///
/// ローカル LLM（Qwen3 等）が出力する `<think>` タグを解析し、
/// 推論コンテンツと応答テキストを分類する。チャンク境界をまたぐタグに対応。
///
/// ## 使用例
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

    /// パース結果のチャンク
    public enum ParsedChunk: Sendable, Equatable {
        /// `<think>` タグ内の推論コンテンツ
        case thinking(String)
        /// `</think>` 以降（またはタグなし）の応答テキスト
        case text(String)
    }

    private enum State: Sendable {
        /// 初期状態: `<think>` の開始を検出中
        case initial
        /// `<think>` 内部の推論コンテンツを読み取り中
        case thinking
        /// `</think>` 以降の応答テキスト
        case text
    }

    private var state: State = .initial
    private var buffer: String = ""

    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    public init() {}

    /// 新しいトークンチャンクを処理し、分類済みチャンクを返す。
    public mutating func process(_ chunk: String) -> [ParsedChunk] {
        var results: [ParsedChunk] = []
        buffer += chunk

        switch state {
        case .initial:
            processInitial(&results)
        case .thinking:
            processThinking(&results)
        case .text:
            // </think> 以降は全て text
            let text = buffer
            buffer = ""
            if !text.isEmpty {
                results.append(.text(text))
            }
        }

        return results
    }

    /// 残りのバッファを flush する。ストリーム終了時に呼び出す。
    public mutating func finalize() -> [ParsedChunk] {
        guard !buffer.isEmpty else { return [] }

        let remaining = buffer
        buffer = ""

        switch state {
        case .initial:
            // タグが完成しなかった場合、テキストとして扱う
            return [.text(remaining)]
        case .thinking:
            // 未閉じの thinking（モデルが途中で打ち切られた場合）
            return [.thinking(remaining)]
        case .text:
            return [.text(remaining)]
        }
    }

    // MARK: - Private

    private mutating func processInitial(_ results: inout [ParsedChunk]) {
        // バッファが <think> のプレフィックスかチェック
        let openTag = Self.openTag

        if buffer.hasPrefix(openTag) {
            // <think> タグを検出 → 消費して thinking 状態へ
            buffer.removeFirst(openTag.count)
            state = .thinking
            // バッファに残りがあれば thinking として処理
            if !buffer.isEmpty {
                processThinking(&results)
            }
        } else if openTag.hasPrefix(buffer) {
            // バッファが <think> の途中（例: "<thi"）→ 保留
            return
        } else {
            // <think> ではない → 全てテキスト
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

        // バッファ内で </think> を検索
        while let range = buffer.range(of: closeTag) {
            // </think> の前の部分を thinking として出力
            let thinkingContent = String(buffer[buffer.startIndex..<range.lowerBound])
            if !thinkingContent.isEmpty {
                results.append(.thinking(thinkingContent))
            }

            // </think> を消費して text 状態へ
            buffer = String(buffer[range.upperBound...])
            state = .text

            // 残りのバッファは text として出力
            if !buffer.isEmpty {
                results.append(.text(buffer))
                buffer = ""
            }
            return
        }

        // </think> が見つからない場合、末尾が部分一致する可能性をチェック
        // 例: バッファが "content</thi" の場合、"</thi" は保留
        let holdBack = partialCloseTagSuffix()
        if holdBack > 0 {
            let emitEnd = buffer.index(buffer.endIndex, offsetBy: -holdBack)
            let thinkingContent = String(buffer[buffer.startIndex..<emitEnd])
            buffer = String(buffer[emitEnd...])
            if !thinkingContent.isEmpty {
                results.append(.thinking(thinkingContent))
            }
        } else {
            // 部分一致なし → 全て thinking として出力
            let thinkingContent = buffer
            buffer = ""
            if !thinkingContent.isEmpty {
                results.append(.thinking(thinkingContent))
            }
        }
    }

    /// バッファ末尾が `</think>` の部分プレフィックスと一致する長さを返す。
    private func partialCloseTagSuffix() -> Int {
        let closeTag = Self.closeTag
        // 末尾から最長一致を探す（1文字 "<" から closeTag.count-1 文字まで）
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
