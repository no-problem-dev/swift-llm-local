import SwiftUI
import LLMLocal
import DesignSystem

struct DownloadProgressView: View {
    let progress: DownloadProgress

    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.xs) {
            ProgressView(value: progress.fraction)
                .tint(colors.primary)

            HStack {
                Text(String(format: "%.0f%%", progress.fraction * 100))
                    .typography(.labelLarge)
                    .foregroundStyle(colors.primary)

                Spacer()

                Text(formattedBytes)
                    .typography(.labelSmall)
                    .foregroundStyle(colors.onSurfaceVariant)
            }

            if let file = progress.currentFile {
                Text(file)
                    .typography(.labelSmall)
                    .foregroundStyle(colors.onSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let completed = formatter.string(fromByteCount: progress.completedBytes)
        let total = formatter.string(fromByteCount: progress.totalBytes)
        return "\(completed) / \(total)"
    }
}
