---
title: "Task Dependency Graph"
created: 2026-02-22
status: draft
references:
  - ./99_dependencies.md
  - ./00_index.md
---

# Task Dependency Graph

## Phase 間依存関係図

```mermaid
flowchart LR
    subgraph Phase1["Phase 1: Core (v0.1.0)"]
        P1["FF-01〜FF-05<br/>Protocol + MLX + Models + Service"]
    end
    subgraph Phase2["Phase 2: Enhanced (v0.2.0)"]
        P2["FF-06〜FF-08<br/>LoRA + Memory + Progress"]
    end
    subgraph Phase3["Phase 3: Nice-to-have (v0.3.0)"]
        P3["FF-09〜FF-10<br/>Background DL + Multi-model"]
    end

    Phase1 --> Phase2
    Phase2 --> Phase3
```

## Wave 間依存関係図

### Phase 1

```mermaid
flowchart TD
    subgraph Phase1["Phase 1: Core"]
        W11["Wave 1-1<br/>Pre-verification + Package"]
        W12["Wave 1-2<br/>LLMLocalClient"]
        W13["Wave 1-3<br/>LLMLocalModels"]
        W14["Wave 1-4<br/>LLMLocalMLX"]
        W15["Wave 1-5<br/>LLMLocal Umbrella"]
        W16["Wave 1-6<br/>Integration Tests"]
        W17["Wave 1-7<br/>E2E + Manual QA"]

        W11 --> W12
        W12 --> W13
        W12 --> W14
        W13 --> W15
        W14 --> W15
        W15 --> W16
        W16 --> W17
    end
```

### Phase 2

```mermaid
flowchart TD
    subgraph Phase2["Phase 2: Enhanced"]
        W21["Wave 2-1<br/>DownloadProgress + Memory"]
        W22["Wave 2-2<br/>LoRA Adapter"]
        W23["Wave 2-3<br/>Integration Tests"]
        W24["Wave 2-4<br/>E2E + Manual QA"]

        W21 --> W23
        W22 --> W23
        W23 --> W24
    end
```

### Phase 3

```mermaid
flowchart TD
    subgraph Phase3["Phase 3: Nice-to-have"]
        W31["Wave 3-1<br/>Background DL + Multi-model"]
        W32["Wave 3-2<br/>Integration + QA"]

        W31 --> W32
    end
```

## Task 間依存関係図

### Phase 1: Wave 1-1 → Wave 1-2

```mermaid
flowchart TD
    subgraph W11["Wave 1-1: Pre-verification + Package"]
        T1["T1: Verify mlx-swift-lm API"]
        T2["T2: Initialize Package.swift"]
    end

    subgraph W12["Wave 1-2: LLMLocalClient"]
        T3["T3: Protocol + model types"]
        T4["T4: Config + Stats + Error"]
    end

    T2 --> T3
    T2 --> T4
```

### Phase 1: Wave 1-2 → Wave 1-3/1-4

```mermaid
flowchart TD
    subgraph W12["Wave 1-2: LLMLocalClient"]
        T3["T3: Protocol + model types"]
        T4["T4: Config + Stats + Error"]
    end

    subgraph W13["Wave 1-3: LLMLocalModels"]
        T5["T5: ModelManager + cache"]
    end

    subgraph W14["Wave 1-4: LLMLocalMLX"]
        T6["T6: MLXBackend"]
    end

    T1["T1: API verification"]

    T3 --> T5
    T4 --> T5
    T1 --> T6
    T3 --> T6
    T4 --> T6
```

### Phase 1: Wave 1-3/1-4 → Wave 1-5 → Wave 1-6 → Wave 1-7

```mermaid
flowchart TD
    subgraph W13["Wave 1-3"]
        T5["T5: ModelManager"]
    end

    subgraph W14["Wave 1-4"]
        T6["T6: MLXBackend"]
    end

    subgraph W15["Wave 1-5: LLMLocal"]
        T7["T7: Umbrella + Service + Presets"]
    end

    subgraph W16["Wave 1-6"]
        T8["T8: Integration Tests"]
    end

    subgraph W17["Wave 1-7"]
        T9["T9: E2E + Manual QA"]
    end

    T5 --> T7
    T6 --> T7
    T7 --> T8
    T8 --> T9
```

### Phase 2: 全タスク依存関係

```mermaid
flowchart TD
    %% Phase 1 dependencies
    T5["T5: ModelManager<br/>(Phase 1)"]
    T6["T6: MLXBackend<br/>(Phase 1)"]
    T7["T7: Service<br/>(Phase 1)"]
    T3["T3: Types<br/>(Phase 1)"]

    subgraph W21["Wave 2-1: Progress + Memory"]
        T10["T10: DownloadProgress"]
        T11["T11: Memory monitoring"]
    end

    subgraph W22["Wave 2-2: LoRA"]
        T12["T12: AdapterManager"]
        T13["T13: MLXBackend + LoRA"]
    end

    subgraph W23["Wave 2-3"]
        T14["T14: Integration Tests"]
    end

    subgraph W24["Wave 2-4"]
        T15["T15: E2E + QA"]
    end

    T5 --> T10
    T6 --> T11
    T7 --> T11
    T3 --> T12
    T5 --> T12
    T6 --> T13
    T12 --> T13
    T10 --> T14
    T11 --> T14
    T12 --> T14
    T13 --> T14
    T14 --> T15
```

### Phase 3: 全タスク依存関係

```mermaid
flowchart TD
    %% Phase 2 dependencies
    T10["T10: DownloadProgress<br/>(Phase 2)"]
    T7["T7: Service<br/>(Phase 1)"]
    T11["T11: Memory<br/>(Phase 2)"]

    subgraph W31["Wave 3-1"]
        T16["T16: Background DL"]
        T17["T17: Multi-model"]
    end

    subgraph W32["Wave 3-2"]
        T18["T18: Integration + QA"]
    end

    T10 --> T16
    T7 --> T17
    T11 --> T17
    T16 --> T18
    T17 --> T18
```

## 全体俯瞰図

```mermaid
flowchart TD
    T1["T1: API verify"] --> T6
    T2["T2: Package.swift"] --> T3["T3: Protocol + types"]
    T2 --> T4["T4: Config + Error"]
    T3 --> T5["T5: ModelManager"]
    T4 --> T5
    T3 --> T6["T6: MLXBackend"]
    T4 --> T6
    T5 --> T7["T7: Umbrella + Service"]
    T6 --> T7
    T7 --> T8["T8: Integration Tests"]
    T8 --> T9["T9: E2E + QA"]

    T5 --> T10["T10: DownloadProgress"]
    T6 --> T11["T11: Memory monitor"]
    T7 --> T11
    T3 --> T12["T12: AdapterManager"]
    T5 --> T12
    T6 --> T13["T13: LoRA merge"]
    T12 --> T13
    T10 --> T14["T14: Phase 2 Tests"]
    T11 --> T14
    T12 --> T14
    T13 --> T14
    T14 --> T15["T15: Phase 2 QA"]

    T10 --> T16["T16: Background DL"]
    T7 --> T17["T17: Multi-model"]
    T11 --> T17
    T16 --> T18["T18: Phase 3 QA"]
    T17 --> T18

    style T1 fill:#e1f5fe
    style T2 fill:#e1f5fe
    style T3 fill:#e1f5fe
    style T4 fill:#e1f5fe
    style T5 fill:#e1f5fe
    style T6 fill:#e1f5fe
    style T7 fill:#e1f5fe
    style T8 fill:#e1f5fe
    style T9 fill:#e1f5fe
    style T10 fill:#fff9c4
    style T11 fill:#fff9c4
    style T12 fill:#fff9c4
    style T13 fill:#fff9c4
    style T14 fill:#fff9c4
    style T15 fill:#fff9c4
    style T16 fill:#e8f5e9
    style T17 fill:#e8f5e9
    style T18 fill:#e8f5e9
```

凡例:
- 青: Phase 1（Core）
- 黄: Phase 2（Enhanced）
- 緑: Phase 3（Nice-to-have）
