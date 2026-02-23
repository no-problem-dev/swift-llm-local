import LLMLocalClient
import MLXLMCommon

extension GenerationConfig {
    /// この ``GenerationConfig`` を MLX の ``GenerateParameters`` に変換します。
    var mlxParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )
    }
}
