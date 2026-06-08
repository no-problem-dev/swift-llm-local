import LLMLocalClient
import MLXLMCommon

extension GenerationConfig {
    /// この ``GenerationConfig`` を MLX の ``GenerateParameters`` に変換します。
    /// 思考モード（``enableThinking``）はサンプリングではなくチャットテンプレートの
    /// 制御なので、ここではなく `applyChatTemplate` の additionalContext で扱います。
    var mlxParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            maxKVSize: maxKVSize,
            kvBits: kvBits,
            kvGroupSize: kvGroupSize,
            temperature: temperature,
            topP: topP,
            topK: topK,
            minP: minP,
            repetitionPenalty: repetitionPenalty,
            repetitionContextSize: repetitionContextSize,
            prefillStepSize: prefillStepSize
        )
    }

    /// チャットテンプレートへ渡す追加コンテキスト。思考モードの抑制フラグを載せる。
    /// Qwen3 系テンプレートは `enable_thinking == false` で空の `<think></think>` を
    /// 注入し、思考生成をスキップさせる。
    var chatTemplateContext: [String: any Sendable]? {
        enableThinking ? nil : ["enable_thinking": false]
    }
}
