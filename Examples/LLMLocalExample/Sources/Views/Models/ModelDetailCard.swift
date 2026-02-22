import SwiftUI
import LLMLocal
import DesignSystem

struct ModelDetailCard: View {
    let spec: ModelSpec
    var sizeHint: String? = nil
    let isCached: Bool
    let isSelected: Bool
    let isDownloadingThis: Bool
    let statusText: String
    let downloadProgress: DownloadProgress?
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    var body: some View {
        Card(elevation: .level1, allSides: 16) {
            VStack(alignment: .leading, spacing: spacing.sm) {
                header
                description

                if isDownloadingThis, let downloadProgress {
                    DownloadProgressView(progress: downloadProgress)
                } else if isDownloadingThis {
                    downloadingIndicator
                }

                actions
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: spacing.xs) {
                    Text(spec.displayName)
                        .typography(.titleMedium)
                        .foregroundStyle(colors.onSurface)
                    if let sizeHint {
                        Text(sizeHint)
                            .typography(.labelSmall)
                            .foregroundStyle(colors.onSurfaceVariant)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.surfaceVariant)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(colors.primary)
            }

            if isCached {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(colors.success)
                    .font(.caption)
            }
        }
    }

    private var description: some View {
        Text(spec.description)
            .typography(.bodyMedium)
            .foregroundStyle(colors.onSurfaceVariant)
    }

    private var downloadingIndicator: some View {
        HStack(spacing: spacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text(statusText)
                .typography(.bodySmall)
                .foregroundStyle(colors.onSurfaceVariant)
        }
    }

    private var actions: some View {
        HStack(spacing: spacing.sm) {
            if isCached {
                Button(action: onSelect) {
                    Text(isSelected ? "選択中" : "選択")
                }
                .buttonStyle(.secondary)
                .buttonSize(.small)
                .disabled(isSelected)

                Button(action: onDelete) {
                    Label("削除", systemImage: "trash")
                }
                .buttonStyle(.tertiary)
                .buttonSize(.small)
            } else {
                Button(action: onDownload) {
                    Label("ダウンロード", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.primary)
                .buttonSize(.small)
                .disabled(isDownloadingThis)
            }
        }
    }
}
