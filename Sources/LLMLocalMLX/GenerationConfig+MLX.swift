import LLMLocalClient
import MLXLMCommon

extension GenerationConfig {
    /// Maps this configuration onto the MLX generation parameters.
    ///
    /// Everything that steers sampling, the KV cache, and prefill crosses over one-to-one.
    /// Thinking mode does not: it is a chat template switch rather than a sampling knob, so it
    /// travels through ``chatTemplateContext`` instead.
    var mlxParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            maxKVSize: maxKVSize,
            kvBits: kvBits,
            kvGroupSize: kvGroupSize,
            quantizedKVStart: quantizedKVStart,
            temperature: temperature,
            topP: topP,
            topK: topK,
            minP: minP,
            repetitionPenalty: repetitionPenalty,
            repetitionContextSize: repetitionContextSize,
            presencePenalty: presencePenalty,
            presenceContextSize: presenceContextSize,
            frequencyPenalty: frequencyPenalty,
            frequencyContextSize: frequencyContextSize,
            prefillStepSize: prefillStepSize
        )
    }

    /// Extra variables handed to the chat template, carrying the thinking-mode switch.
    ///
    /// Qwen3-style templates read `enable_thinking == false` and emit an empty `<think></think>`
    /// span, which makes the model skip reasoning and answer directly. Returns `nil` when thinking
    /// is enabled, leaving the template at its own default.
    ///
    /// A model whose template ignores the flag simply keeps thinking; nothing reports that the
    /// request had no effect.
    var chatTemplateContext: [String: any Sendable]? {
        enableThinking ? nil : ["enable_thinking": false]
    }
}
