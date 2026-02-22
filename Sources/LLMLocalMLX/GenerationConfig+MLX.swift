import LLMLocalClient
import MLXLMCommon

extension GenerationConfig {
    /// Converts this ``GenerationConfig`` to MLX ``GenerateParameters``.
    var mlxParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )
    }
}
