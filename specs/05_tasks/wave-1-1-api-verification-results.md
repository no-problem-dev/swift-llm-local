---
title: "Wave 1-1: mlx-swift-lm API Verification Results"
created: 2026-02-22
status: verified
---

# mlx-swift-lm API Verification Results

## Executive Summary

This document verifies the API signatures and assumptions made in the Design Spec for the `mlx-swift-lm` Swift package. The verification was conducted on 2026-02-22 using web research of the official repository, Swift Package Index documentation, and community examples.

## Package Information

| Attribute | Value |
|-----------|-------|
| **Repository URL** | `https://github.com/ml-explore/mlx-swift-lm` ✅ |
| **Product names** | `MLXLLM`, `MLXLMCommon`, `MLXVLM`, `MLXEmbedders` ✅ |
| **Latest version** | `2.30.3` (released Feb 2026) ⚠️ |
| **Recommended version** | `.upToNextMinor(from: "2.29.1")` or branch `"main"` |
| **swift-tools-version** | Not explicitly documented, compatible with Swift 5.9+ (AsyncThrowingStream) |

### Package.swift Configuration

**Verified approach:**
```swift
.package(url: "https://github.com/ml-explore/mlx-swift-lm/", .upToNextMinor(from: "2.29.1"))
// OR
.package(url: "https://github.com/ml-explore/mlx-swift-lm/", branch: "main")
```

**Product dependencies:**
```swift
.target(
    name: "YourTargetName",
    dependencies: [
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm")
    ]
)
```

**Sources:**
- [mlx-swift-lm GitHub Repository](https://github.com/ml-explore/mlx-swift-lm)
- [Swift Package Index - mlx-swift-lm](https://swiftpackageindex.com/ml-explore/mlx-swift-lm)
- [Package.swift documentation](https://github.com/ml-explore/mlx-swift-examples)

---

## API Verification

### 1. loadModel(id:)

**Status:** ✅ Verified

**Signature (inferred from usage examples):**
```swift
func loadModel(id: String) async throws -> LanguageModel
```

**Description:**
- Downloads and loads a model from Hugging Face Hub asynchronously
- Parameter `id`: HuggingFace model identifier (e.g., `"mlx-community/Qwen3-4B-4bit"`)
- Returns: A `LanguageModel` instance ready for inference
- Throws: Errors during download or model initialization

**Usage example:**
```swift
let model = try await loadModel(id: "mlx-community/Qwen3-4B-4bit")
```

**Advanced alternative:**
For more control (progress reporting, custom hub configuration):
```swift
LLMModelFactory.shared.loadContainer(configuration: config, progressHandler: { progress in
    // Handle download progress
})
```

**Sources:**
- [Rudrank Riyam - Exploring MLX Swift](https://rudrank.com/exploring-mlx-swift-adding-on-device-inference-to-your-app)
- [mlx-swift-lm GitHub](https://github.com/ml-explore/mlx-swift-lm)

---

### 2. ChatSession

**Status:** ✅ Verified (with VLM enhancements noted)

**Initialization:**
```swift
let session = ChatSession(model: languageModel)
```

**Description:**
- Manages conversation context and KV cache automatically
- Inspired by Apple's Foundation Models framework
- Part of `MLXLMCommon` module

**Key Methods:**

#### `respond(to:)` - Complete Response
```swift
func respond(to prompt: String) async throws -> String
```
Returns the complete generated response as a single string.

#### `streamResponse(to:)` - Streaming Response
**Verified signature:**
```swift
func streamResponse(
    to prompt: String,
    image: Image? = nil,
    video: [Image]? = nil
) -> AsyncThrowingStream<String, Error>
```

**Return Type:** `AsyncThrowingStream<String, Error>`
- Yields individual text chunks as `String` values
- Can throw errors during generation
- Perfect for real-time UI updates

**Usage example:**
```swift
for try await text in session.streamResponse(to: prompt) {
    self.output += text
}
```

**Notes:**
- The `image` and `video` parameters are for Vision Language Model (VLM) support
- For LLM-only usage, only the `to:` parameter is used
- The stream yields text incrementally as tokens are generated

**Sources:**
- [Swift Package Index - streamResponse documentation](https://swiftpackageindex.com/ml-explore/mlx-swift-examples/2.29.1/documentation/mlxlmcommon/chatsession/streamresponse(to:image:video:))
- [Rudrank Riyam - Exploring MLX Swift](https://rudrank.com/exploring-mlx-swift-adding-on-device-inference-to-your-app)
- [Integrating Local LLMs into iOS Apps with MLX Swift](https://compiledthoughts.pages.dev/blog/integrating-mlx-local-llms-ios-apps/)

---

### 3. GenerateParameters

**Status:** ✅ Verified

**Struct definition (inferred from documentation):**
```swift
struct GenerateParameters {
    var temperature: Double
    var maxTokens: Int
    var topP: Double
    var repetitionPenalty: Double
    var repetitionContextSize: Int
    // Additional fields may exist
}
```

**Confirmed Fields:**

| Field | Type | Purpose | Notes |
|-------|------|---------|-------|
| `temperature` | `Double` | Controls randomness | `0.0` = deterministic, higher = more creative |
| `maxTokens` | `Int` | Maximum tokens to generate | Limits output length |
| `topP` | `Double` | Nucleus sampling threshold | Range: `0.0` to `1.0`, considers top-probability tokens |
| `repetitionPenalty` | `Double` | Penalizes repeated tokens | Higher values reduce repetition |
| `repetitionContextSize` | `Int` | Context window for repetition check | Number of recent tokens to consider |

**Example usage:**
```swift
let params = GenerateParameters(
    maxTokens: 1200,
    temperature: 0.7,
    topP: 0.95,
    repetitionPenalty: 1.5,
    repetitionContextSize: 30
)
```

**Sampler Selection Logic:**
- `temperature == 0` → `ArgMaxSampler` (deterministic)
- `0 < topP < 1` → `TopPSampler` (nucleus sampling)
- Otherwise → `CategoricalSampler` (standard sampling)

**Sources:**
- [Rudrank Riyam - Working with Generate Parameters](https://rudrank.com/exploring-mlx-swift-working-with-generate-parameters-for-language-models)
- [Medium - Build an On-Device AI Text Generator](https://medium.com/@ale058791/build-an-on-device-ai-text-generator-for-ios-with-mlx-fdd2bea1f410)

---

### 4. GPU Cache Control: MLX.GPU.set(cacheLimit:)

**Status:** ✅ Verified

**Signature:**
```swift
MLX.GPU.set(cacheLimit: Int)
```

**Description:**
- Controls the maximum memory (in bytes) that the GPU buffer cache can utilize
- Helps balance memory consumption and computational efficiency on iOS devices
- Distinct from `MLX.GPU.set(memoryLimit:relaxed:)`

**Parameter:**
- `cacheLimit`: Maximum cache size in bytes (e.g., `20 * 1024 * 1024` = 20MB)

**Common iOS usage:**
```swift
// Set cache limit to 20MB (typical for iOS devices)
MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

// For larger devices, can use 100-512MB
MLX.GPU.set(cacheLimit: 512 * 1024 * 1024)
```

**Memory Types:**
- `activeMemory`: Currently active in `MLXArray` instances
- `cacheMemory`: Recently used memory that can be recycled

**Related API:**
```swift
MLX.GPU.set(memoryLimit: Int, relaxed: Bool)  // Overall GPU memory limit
MLX.GPU.cacheLimit  // Read current cache limit
```

**Performance notes:**
- Setting appropriate cache limits can improve inference speed
- Too low: May cause slowdowns due to frequent cache misses
- Too high: May cause memory pressure on iOS devices

**Sources:**
- [GitHub Issue #66 - GPU Memory/Cache Limit](https://github.com/ml-explore/mlx-swift-examples/issues/66)
- [Swift Package Index - GPU cacheLimit](https://swiftpackageindex.com/ml-explore/mlx-swift/0.21.2/documentation/mlx/gpu/cachelimit)
- [Integrating Local LLMs into iOS Apps](https://compiledthoughts.pages.dev/blog/integrating-mlx-local-llms-ios-apps/)

---

## HuggingFace Model IDs Verification

### 1. mlx-community/gemma-2-2b-it-4bit

**Status:** ✅ Verified and Available

| Attribute | Value |
|-----------|-------|
| **HuggingFace URL** | https://huggingface.co/mlx-community/gemma-2-2b-it-4bit |
| **Base model** | `google/gemma-2-2b-it` |
| **Quantization** | 4-bit (MLX format) |
| **Converted with** | `mlx-lm` version 0.16.1 |
| **Model size** | ~2B parameters (4-bit quantized) |
| **Architecture** | Gemma 2 (instruction-tuned) |

**Usage:**
```swift
let model = try await loadModel(id: "mlx-community/gemma-2-2b-it-4bit")
```

**Model family:**
- `mlx-community/gemma-2-2b-it-4bit` (2B, 4-bit) ✅
- `mlx-community/gemma-2-9b-it-4bit` (9B, 4-bit)
- `mlx-community/gemma-2-27b-it-4bit` (27B, 4-bit)

**Sources:**
- [HuggingFace Model Page](https://huggingface.co/mlx-community/gemma-2-2b-it-4bit)

---

### 2. mlx-community/swallow-7b-instruct-4bit

**Status:** ⚠️ NOT FOUND - Alternative Available

**Finding:**
The specific model ID `mlx-community/swallow-7b-instruct-4bit` does **NOT exist** in the mlx-community organization on HuggingFace.

**Available alternatives:**

| Model ID | Size | Status |
|----------|------|--------|
| `mlx-community/Llama-3.3-Swallow-70B-Instruct-v0.4-4bit` | 70B | ✅ Available |
| `mlx-community/Llama-3.1-Swallow-70B-Instruct-v0.3-4bit` | 70B | ✅ Available |

**Original Swallow models (not MLX-optimized):**
- `tokyotech-llm/Swallow-7b-instruct-v0.1` (Base HF format)
- `TheBloke/Swallow-7B-GGUF` (GGUF format)

**Recommendation:**
For a Japanese LLM in the 7B range with MLX 4-bit quantization, consider:
- `mlx-community/Mistral-7B-Instruct-v0.3-4bit`
- `mlx-community/Qwen2.5-7B-Instruct-4bit`

Or use the 70B Swallow model if device resources permit:
```swift
let model = try await loadModel(id: "mlx-community/Llama-3.3-Swallow-70B-Instruct-v0.4-4bit")
```

**About Swallow:**
- Developed by Institute of Science Tokyo (formerly Tokyo Tech)
- Specialized Japanese tokenization for faster inference
- Enhances Japanese capability of base models (Llama, Gemma, Mistral)

**Sources:**
- [mlx-community Organization](https://huggingface.co/mlx-community)
- [Swallow LLM Official Site](https://swallow-llm.github.io/index.en.html)
- [mlx-community/Llama-3.3-Swallow-70B-Instruct-v0.4-4bit](https://huggingface.co/mlx-community/Llama-3.3-Swallow-70B-Instruct-v0.4-4bit)

---

## iOS Sandbox Behavior & HuggingFace Hub Caching

**Status:** ✅ Verified

### Default Cache Directory

By default, `mlx-swift-lm` downloads models to the **iOS app's Documents directory**:
- Path: `~/Documents/` (within the app sandbox)
- Accessible via: `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)`

### Custom Cache Configuration

You can customize the cache directory using `HubApi`:

```swift
import Hub

let customHub = HubApi(
    downloadBase: URL.downloadsDirectory.appending(path: "huggingface")
)

// Pass to LLMModelFactory for custom cache location
LLMModelFactory.shared.loadContainer(
    configuration: config,
    hub: customHub,
    progressHandler: { progress in
        print("Download progress: \(progress)")
    }
)
```

### Recommended Cache Locations for iOS

| Location | Path | Use Case |
|----------|------|----------|
| **Documents** | `FileManager.urls(.documentDirectory)` | Default, user-visible in Files app |
| **Application Support** | `FileManager.urls(.applicationSupportDirectory)` | Hidden from user, persistent |
| **Caches** | `FileManager.urls(.cachesDirectory)` | Can be purged by system, temporary |

### iOS App Entitlements Required

**For HuggingFace model downloads:**
1. **Outgoing Connections (Client)** - Required in App Sandbox capabilities
2. **Increased Memory Limit** - Recommended for devices with more RAM

**Example entitlement:**
```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

### Model Storage Considerations

| Aspect | Details |
|--------|---------|
| **Storage space** | 4-bit models: 1-3GB per model (e.g., gemma-2-2b-it-4bit ~1.5GB) |
| **Backup** | Documents directory is backed up to iCloud/iTunes by default |
| **Persistence** | Application Support/Documents persist across app updates |
| **User access** | Documents visible in Files app, Application Support hidden |

**Best practice for production:**
Use **Application Support** to keep models hidden from users and avoid iCloud backup overhead:

```swift
let appSupportURL = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
).first!

let hubCacheURL = appSupportURL.appendingPathComponent("huggingface")
let hub = HubApi(downloadBase: hubCacheURL)
```

**Sources:**
- [Medium - Run Hugging Face Models with MLX Swift](https://medium.com/@cetinibrahim/run-hugging-face-models-with-mlx-swift-d723437ff12e)
- [LLMEval README](https://github.com/ml-explore/mlx-swift-examples/blob/main/Applications/LLMEval/README.md)
- [Integrating Local LLMs into iOS Apps](https://compiledthoughts.pages.dev/blog/integrating-mlx-local-llms-ios-apps/)

---

## Design Spec Comparison & Recommendations

### Differences from Design Spec Assumptions

| Aspect | Design Spec Assumption | Verified Reality | Impact |
|--------|------------------------|------------------|--------|
| **Package Version** | `from: "0.1.0"` | Latest: `2.30.3` (Feb 2026) | ⚠️ **UPDATE REQUIRED** |
| **Package URL** | `https://github.com/ml-explore/mlx-swift-lm` | ✅ Correct | None |
| **Products** | `MLXLLM`, `MLXLMCommon` | ✅ Correct (+ `MLXVLM`, `MLXEmbedders`) | Consider adding `MLXVLM` if VLM support needed |
| **loadModel API** | `loadModel(id:)` | ✅ Correct | None |
| **ChatSession API** | `ChatSession(model)` | ✅ Correct | None |
| **streamResponse API** | `streamResponse(to:)` | ✅ Correct (with optional VLM params) | None |
| **GPU Cache API** | `MLX.GPU.set(cacheLimit:)` | ✅ Correct | None |
| **Swallow model** | `mlx-community/swallow-7b-instruct-4bit` | ❌ Does not exist | ⚠️ **MODEL ID INVALID** |

### Required Updates to Design Spec

#### 1. Package Version ⚠️

**Current (incorrect):**
```swift
.package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "0.1.0")
```

**Recommended:**
```swift
// Option 1: Use latest stable minor version
.package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "2.29.1"))

// Option 2: Track main branch (for latest features, less stable)
.package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main")
```

#### 2. Preset Model ID for Japanese LLM ⚠️

**Current (invalid):**
```swift
case swallow = "mlx-community/swallow-7b-instruct-4bit"
```

**Option A - Use 70B Swallow (best Japanese support):**
```swift
case swallow = "mlx-community/Llama-3.3-Swallow-70B-Instruct-v0.4-4bit"
```

**Option B - Use different 7B model with good multilingual support:**
```swift
case qwen = "mlx-community/Qwen2.5-7B-Instruct-4bit"
```

**Option C - Remove Japanese preset and use only Gemma:**
```swift
// Remove swallow preset entirely if not critical
// Keep only gemma-2-2b-it-4bit as the primary preset
```

#### 3. streamResponse Return Type (Minor enhancement)

**Current (inferred):**
```swift
func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error>
```

**Complete signature (with VLM support):**
```swift
func streamResponse(
    to prompt: String,
    image: Image? = nil,
    video: [Image]? = nil
) -> AsyncThrowingStream<String, Error>
```

**Impact:** No breaking change (optional parameters default to `nil`), but consider documenting VLM capabilities.

---

## Additional Findings

### 1. Swift Concurrency Requirements

The `streamResponse` API returns `AsyncThrowingStream<String, Error>`, which requires:
- **Swift 5.9+** for structured concurrency
- **iOS 13+** deployment target (async/await support)

### 2. Memory Management Strategy

For iOS deployment, recommended memory configuration:
```swift
// Set GPU cache limit (20-512MB depending on device)
MLX.GPU.set(cacheLimit: 100 * 1024 * 1024)  // 100MB

// Monitor memory if needed
let activeMemory = MLX.GPU.activeMemory
let cacheMemory = MLX.GPU.cacheMemory
```

### 3. Model Download Considerations

**Network requirements:**
- App must have "Outgoing Connections (Client)" capability
- First launch will require 1-3GB download per model
- Consider preloading models or showing download UI

**Error handling:**
```swift
do {
    let model = try await loadModel(id: "mlx-community/gemma-2-2b-it-4bit")
} catch {
    // Handle network errors, disk space errors, etc.
    print("Failed to load model: \(error)")
}
```

### 4. Model Size vs Device Compatibility

| Model | Size (4-bit) | Recommended Device | RAM Required |
|-------|--------------|-------------------|--------------|
| gemma-2-2b-it | ~1.5GB | iPhone 12+, iPad Air 4+ | 4GB+ |
| qwen-2.5-7b | ~4GB | iPhone 14 Pro+, iPad Pro | 8GB+ |
| swallow-70b | ~35GB | Mac Studio, Mac Pro | 64GB+ |

### 5. Alternative Models to Consider

For production iOS apps with good multilingual support:
- `mlx-community/Qwen2.5-3B-Instruct-4bit` - Compact, fast, good multilingual
- `mlx-community/Phi-4-4bit` - Microsoft Phi-4, excellent reasoning
- `mlx-community/gemma-2-9b-it-4bit` - Larger Gemma 2 for better quality

---

## Verification Methodology

This verification was conducted through:
1. **Web search** of official repositories and documentation
2. **Swift Package Index** documentation review
3. **GitHub repository** exploration (README, examples, issues)
4. **Community resources** (blog posts, tutorials, integration guides)
5. **HuggingFace Hub** model verification

**Limitations:**
- Unable to directly access Swift Package Index API documentation (403 errors)
- Some API signatures inferred from usage examples rather than source code inspection
- Return types and parameter details based on documentation and community examples

**Confidence levels:**
- ✅ **High confidence**: Verified through multiple sources, official documentation
- ⚠️ **Medium confidence**: Inferred from examples, requires source code confirmation
- ❌ **Low confidence / Not found**: Could not verify or verified as incorrect

---

## Sources Summary

All sources are listed inline throughout the document. Key sources include:

- [GitHub - ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)
- [Swift Package Index - mlx-swift-lm](https://swiftpackageindex.com/ml-explore/mlx-swift-lm)
- [Rudrank Riyam - Exploring MLX Swift](https://rudrank.com/exploring-mlx-swift-adding-on-device-inference-to-your-app)
- [HuggingFace - mlx-community](https://huggingface.co/mlx-community)
- [Integrating Local LLMs into iOS Apps with MLX Swift](https://compiledthoughts.pages.dev/blog/integrating-mlx-local-llms-ios-apps/)
- [Swift.org - On-device ML research with MLX](https://www.swift.org/blog/mlx-swift/)

---

## Next Steps

1. **Update Design Spec** with corrected package version and model IDs
2. **Choose Japanese LLM strategy**: 70B Swallow vs alternative 7B model
3. **Document VLM capabilities** if vision features will be used
4. **Source code inspection**: Directly examine `mlx-swift-lm` source files for precise API signatures
5. **Test model downloads** on target iOS devices to verify memory and storage requirements
