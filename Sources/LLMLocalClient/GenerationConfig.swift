/// Settings that control one generation: sampling, KV cache budget, and thinking mode.
///
/// The fields map one-to-one onto the MLX `GenerateParameters` knobs, with one exception:
/// ``enableThinking`` is not a sampling setting at all, it is a flag passed to the chat template.
/// A backend applies the whole value per call, so two calls with different configs need no reload.
///
/// Several knobs disable themselves at specific values rather than being validated, so a
/// combination that looks active can be inert — the notes on each field say which value is off.
public struct GenerationConfig: Sendable, Hashable, Codable {
    // MARK: - Length

    /// Budget for tokens the model may generate this turn; prompt tokens do not count against it.
    ///
    /// `nil` means no budget: generation runs until the model emits a stop token or the caller
    /// cancels the stream. It is not clamped to ``ModelSpec/contextLength`` — nothing in this
    /// package enforces that number — so on a long conversation the cap that actually bites is
    /// ``maxKVSize`` or device memory.
    public var maxTokens: Int?

    // MARK: - Sampling

    /// Softmax temperature; lower is more deterministic, and exactly `0` is greedy decoding.
    ///
    /// At `0` MLX swaps in an arg-max sampler, which ignores ``topP``, ``topK``, and ``minP``
    /// entirely — tuning them alongside a zero temperature has no effect. Use `0` for tool calls
    /// and structured output where a single reproducible answer matters.
    public var temperature: Float
    /// Nucleus sampling threshold, active only for values strictly between 0 and 1.
    ///
    /// `1.0` (and `0`) turn it off rather than making it maximally permissive.
    public var topP: Float
    /// Number of highest-probability tokens to sample from; `0` disables the filter.
    public var topK: Int
    /// Probability floor relative to the most likely token; `0` disables the filter.
    public var minP: Float
    /// Multiplicative penalty on tokens already seen in the recent window; `nil` or `0` disables it.
    ///
    /// Values around 1.05–1.1 are the usual range for stopping small models from looping. It also
    /// goes inert if ``repetitionContextSize`` is not positive.
    public var repetitionPenalty: Float?
    /// How many of the most recent tokens the repetition penalty looks at.
    public var repetitionContextSize: Int
    /// Additive penalty applied once to any token present in the recent window, as in the OpenAI API.
    ///
    /// `nil` or `0` disables it, as does a non-positive ``presenceContextSize``.
    public var presencePenalty: Float?
    /// How many of the most recent tokens the presence penalty looks at.
    public var presenceContextSize: Int
    /// Additive penalty scaled by how often a token occurs in the recent window, as in the OpenAI API.
    ///
    /// `nil` or `0` disables it, as does a non-positive ``frequencyContextSize``.
    public var frequencyPenalty: Float?
    /// How many of the most recent tokens the frequency penalty looks at.
    public var frequencyContextSize: Int

    // MARK: - KV Cache (memory and long context)

    /// Bit width for KV cache quantization, 4 or 8; `nil` keeps the cache unquantized.
    ///
    /// This is the main lever on memory for long contexts, at some cost in output quality.
    public var kvBits: Int?
    /// Hard ceiling on cached tokens, or `nil` for an unbounded cache.
    ///
    /// Setting it switches MLX to a rotating cache: once the limit is reached, old entries other
    /// than the first four tokens are overwritten. Generation does not stop and no error is raised,
    /// so the model quietly loses the middle of a long conversation instead of running out of memory.
    public var maxKVSize: Int?
    /// Group size used when quantizing the KV cache.
    public var kvGroupSize: Int
    /// Token position at which KV quantization starts, honoured only when ``kvBits`` is set.
    ///
    /// Early tokens carry more of the attention weight for everything that follows, so leaving the
    /// opening tokens unquantized trades a little memory for noticeably better output. `0`
    /// quantizes from the first token.
    public var quantizedKVStart: Int

    // MARK: - Prefill

    /// How many prompt tokens are processed per prefill step.
    public var prefillStepSize: Int

    // MARK: - Thinking

    /// Whether the model is allowed to produce a reasoning span before its answer.
    ///
    /// This is not a sampling setting: `false` passes `enable_thinking: false` into the chat
    /// template, and templates that honour it (Qwen3 and relatives) open and immediately close the
    /// think block so no reasoning tokens are generated. That removes the tokens themselves, not
    /// just their display, which is why agent and tool-calling turns are much faster with it off.
    /// Models whose template ignores the flag keep thinking regardless.
    public var enableThinking: Bool

    public init(
        maxTokens: Int? = nil,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int = 0,
        minP: Float = 0,
        repetitionPenalty: Float? = nil,
        repetitionContextSize: Int = 20,
        presencePenalty: Float? = nil,
        presenceContextSize: Int = 20,
        frequencyPenalty: Float? = nil,
        frequencyContextSize: Int = 20,
        kvBits: Int? = nil,
        maxKVSize: Int? = nil,
        kvGroupSize: Int = 64,
        quantizedKVStart: Int = 0,
        prefillStepSize: Int = 512,
        enableThinking: Bool = true
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.repetitionPenalty = repetitionPenalty
        self.repetitionContextSize = repetitionContextSize
        self.presencePenalty = presencePenalty
        self.presenceContextSize = presenceContextSize
        self.frequencyPenalty = frequencyPenalty
        self.frequencyContextSize = frequencyContextSize
        self.kvBits = kvBits
        self.maxKVSize = maxKVSize
        self.kvGroupSize = kvGroupSize
        self.quantizedKVStart = quantizedKVStart
        self.prefillStepSize = prefillStepSize
        self.enableThinking = enableThinking
    }

    /// Balanced chat defaults: temperature 0.7, nucleus sampling at 0.9, no penalties, no KV
    /// quantization, thinking enabled.
    ///
    /// These are deliberately not the MLX library defaults. Agent and tool-calling work wants a
    /// lower temperature and ``enableThinking`` off, which is what the per-model
    /// ``ModelSpec/recommendedGeneration`` carries.
    public static let `default` = GenerationConfig()
}
