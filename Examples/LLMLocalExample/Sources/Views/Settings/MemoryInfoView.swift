import SwiftUI
import LLMLocal
import DesignSystem

struct MemoryInfoView: View {
    @Environment(ModelState.self) private var modelState
    @Environment(\.colorPalette) private var colors

    var body: some View {
        Section("デバイスメモリ") {
            if let tier = modelState.memoryTier {
                LabeledContent("メモリ階層") {
                    Text(tierLabel(tier))
                        .foregroundStyle(colors.primary)
                }
            }

            LabeledContent("利用可能メモリ") {
                Text(formattedMemory(modelState.availableMemory))
                    .monospacedDigit()
            }

            if let contextLength = modelState.recommendedContextLength {
                LabeledContent("推奨コンテキスト長") {
                    Text("\(contextLength) トークン")
                        .foregroundStyle(colors.primary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func tierLabel(_ tier: MemoryMonitor.DeviceMemoryTier) -> String {
        switch tier {
        case .standard: "標準 (8GB)"
        case .high: "高性能 (12GB+)"
        }
    }

    private func formattedMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
