import SwiftUI
import DesignSystem
import LLMLocal

struct ChatView: View {
    @Environment(ChatState.self) private var chatState
    @Environment(ModelState.self) private var modelState
    @Environment(SettingsState.self) private var settingsState
    @Environment(ToolState.self) private var toolState
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    private var isModelReady: Bool {
        modelState.isModelCached(modelState.selectedModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                streamingBubble
                if !isModelReady {
                    modelNotReadyBanner
                }
                if let error = chatState.error {
                    errorBanner(error)
                }
                InputBar(
                    text: Bindable(chatState).inputText,
                    isGenerating: chatState.isActive || !isModelReady,
                    onSend: sendMessage,
                    onCancel: { chatState.cancelGeneration() }
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("チャット")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    modelBadge
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("コピー", systemImage: "doc.on.doc") {
                        let text = chatState.formatSession(
                            model: modelState.selectedModel,
                            config: settingsState.config,
                            systemPrompt: settingsState.systemPrompt
                        )
                        UIPasteboard.general.string = text
                    }
                    .disabled(chatState.messages.isEmpty)

                    Button("クリア", systemImage: "trash") {
                        chatState.clearMessages()
                    }
                    .disabled(chatState.messages.isEmpty && !chatState.isActive)
                }
            }
        }
    }

    // MARK: - Subviews

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: spacing.sm) {
                    if chatState.messages.isEmpty && !chatState.isActive {
                        emptyState
                    }
                    ForEach(chatState.messages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, spacing.md)
                .padding(.vertical, spacing.sm)
            }
            .onChange(of: chatState.messages.count) {
                if let last = chatState.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(for message: ChatMessage) -> some View {
        switch message.role {
        case .user, .assistant:
            MessageBubble(message: message)
        case .toolCall, .toolResult:
            ToolCallBubble(message: message)
        }
    }

    @ViewBuilder
    private var streamingBubble: some View {
        if chatState.isActive {
            HStack {
                VStack(alignment: .leading, spacing: spacing.xs) {
                    switch chatState.phase {
                    case .loadingModel:
                        HStack(spacing: spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("モデル読み込み中...")
                                .typography(.bodyMedium)
                                .foregroundStyle(colors.onSurfaceVariant)
                        }
                    case .executingTool(let name):
                        HStack(spacing: spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("ツール実行中: \(name)")
                                .typography(.bodyMedium)
                                .foregroundStyle(colors.onSurfaceVariant)
                        }
                    case .generating where !chatState.streamingContent.isEmpty:
                        StreamingResponseView(
                            content: chatState.streamingContent,
                            isStreaming: true
                        )
                    default:
                        HStack(spacing: spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("生成中...")
                                .typography(.bodyMedium)
                                .foregroundStyle(colors.onSurfaceVariant)
                        }
                    }
                }
                .padding(spacing.md)
                .background(colors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer(minLength: spacing.xxl)
            }
            .padding(.horizontal, spacing.md)
        }
    }

    private var emptyState: some View {
        VStack(spacing: spacing.md) {
            Image(systemName: isModelReady ? "brain.head.profile" : "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(colors.onSurfaceVariant.opacity(0.5))
            Text(isModelReady ? "会話を始めましょう" : "モデルをダウンロードしてください")
                .typography(.titleMedium)
                .foregroundStyle(colors.onSurfaceVariant)
            Text(isModelReady
                 ? "ローカル LLM に何でも聞いてみてください"
                 : "「モデル」タブからモデルをダウンロードすると会話できます")
                .typography(.bodyMedium)
                .foregroundStyle(colors.onSurfaceVariant.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var modelBadge: some View {
        Text(modelState.selectedModel.displayName)
            .font(.caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colors.primaryContainer)
            .foregroundStyle(colors.onPrimaryContainer)
            .clipShape(Capsule())
    }

    private var modelNotReadyBanner: some View {
        HStack {
            Image(systemName: "arrow.down.circle")
            Text("「モデル」タブから \(modelState.selectedModel.displayName) をダウンロードしてください")
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(colors.onSecondaryContainer)
        .padding(spacing.sm)
        .frame(maxWidth: .infinity)
        .background(colors.secondaryContainer)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(colors.onError)
        .padding(spacing.sm)
        .frame(maxWidth: .infinity)
        .background(colors.error)
    }

    // MARK: - Actions

    private func sendMessage() {
        chatState.send(
            model: modelState.selectedModel,
            config: settingsState.config,
            toolState: toolState,
            systemPrompt: settingsState.systemPrompt
        )
    }
}
