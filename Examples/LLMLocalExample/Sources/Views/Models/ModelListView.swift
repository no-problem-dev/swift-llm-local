import SwiftUI
import LLMLocal
import DesignSystem

struct ModelListView: View {
    @Environment(ModelState.self) private var modelState
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: spacing.md) {
                    cacheSummary

                    ForEach(ModelCategory.allCases, id: \.rawValue) { category in
                        let entries = ModelCatalog.models(for: category)
                        if !entries.isEmpty {
                            categorySection(category, entries: entries)
                        }
                    }

                    if let error = modelState.error {
                        errorView(error)
                    }
                }
                .padding(spacing.md)
            }
            .navigationTitle("モデル")
            .refreshable {
                await modelState.refreshCache()
            }
        }
    }

    // MARK: - Subviews

    private func categorySection(_ category: ModelCategory, entries: [CatalogEntry]) -> some View {
        VStack(alignment: .leading, spacing: spacing.sm) {
            Text(category.rawValue)
                .typography(.titleSmall)
                .foregroundStyle(colors.onSurfaceVariant)
                .padding(.horizontal, 4)

            ForEach(entries, id: \.spec.id) { entry in
                ModelDetailCard(
                    spec: entry.spec,
                    sizeHint: entry.sizeHint,
                    isCached: modelState.isModelCached(entry.spec),
                    isSelected: modelState.selectedModel == entry.spec,
                    isDownloadingThis: modelState.downloadingModelId == entry.spec.id,
                    statusText: modelState.downloadStatusText,
                    downloadProgress: modelState.downloadingModelId == entry.spec.id
                        ? modelState.downloadProgress : nil,
                    onDownload: { Task { await modelState.downloadModel(entry.spec) } },
                    onDelete: { Task { await modelState.deleteModel(entry.spec) } },
                    onSelect: { modelState.selectedModel = entry.spec }
                )
            }
        }
    }

    private var cacheSummary: some View {
        Card(elevation: .level1, allSides: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("キャッシュ")
                        .typography(.titleSmall)
                        .foregroundStyle(colors.onSurface)
                    Text("\(modelState.cachedModels.count) モデル")
                        .typography(.bodyMedium)
                        .foregroundStyle(colors.onSurfaceVariant)
                }
                Spacer()
                Text(formattedCacheSize)
                    .typography(.headlineMedium)
                    .foregroundStyle(colors.primary)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(colors.error)
            Text(message)
                .typography(.bodySmall)
                .foregroundStyle(colors.error)
        }
        .padding(spacing.sm)
    }

    private var formattedCacheSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: modelState.totalCacheSize)
    }
}
