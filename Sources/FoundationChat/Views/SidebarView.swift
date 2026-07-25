import SwiftUI

struct SidebarView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var searchText = ""
    @State private var conversationPendingDeletion: Conversation?

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return viewModel.conversations }
        return viewModel.conversations.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.messages.contains {
                    $0.content.localizedStandardContains(searchText)
                }
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        GeometryReader { geometry in
            let footerHeight: CGFloat = viewModel.selectedConversation == nil
                ? 76
                : 112

            List(selection: $viewModel.selectedConversationID) {
                Section("Чаты") {
                    ForEach(filteredConversations) { conversation in
                        ConversationRow(conversation: conversation)
                            .tag(conversation.id)
                            .contextMenu {
                                Button("Удалить", systemImage: "trash", role: .destructive) {
                                    conversationPendingDeletion = conversation
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(
                text: $searchText,
                placement: .sidebar,
                prompt: "Поиск по чатам"
            )
            .overlay {
                if filteredConversations.isEmpty {
                    ContentUnavailableView {
                        Label(
                            searchText.isEmpty ? "Нет чатов" : "Ничего не найдено",
                            systemImage: searchText.isEmpty
                                ? "bubble.left.and.bubble.right"
                                : "magnifyingglass"
                        )
                    } description: {
                        if searchText.isEmpty {
                            Text("Создайте чат кнопкой в панели инструментов.")
                        }
                    }
                }
            }
            .frame(
                width: geometry.size.width,
                height: max(0, geometry.size.height - footerHeight)
            )
            .position(
                x: geometry.size.width / 2,
                y: max(0, geometry.size.height - footerHeight) / 2
            )

            ModelStatusFooter()
                .frame(width: geometry.size.width)
                .frame(height: footerHeight)
                .position(
                    x: geometry.size.width / 2,
                    y: max(footerHeight / 2, geometry.size.height - footerHeight / 2)
                )
                .zIndex(1)
        }
        .confirmationDialog(
            "Удалить «\(conversationPendingDeletion?.title ?? "")»?",
            isPresented: Binding(
                get: { conversationPendingDeletion != nil },
                set: { if !$0 { conversationPendingDeletion = nil } }
            )
        ) {
            Button("Удалить", role: .destructive) {
                if let id = conversationPendingDeletion?.id {
                    viewModel.deleteConversation(id)
                }
                conversationPendingDeletion = nil
            }
        } message: {
            Text("Чат будет удалён без возможности восстановления.")
        }
    }
}

private struct ModelStatusFooter: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.modelType.iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.modelType.displayName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(viewModel.currentReadiness.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                statusIndicator
            }

            if viewModel.selectedConversation != nil {
                ProgressView(value: viewModel.contextInfo.usageRatio)
                    .tint(contextColor)
                    .controlSize(.mini)

                HStack {
                    Text(tokenLabel)
                    Spacer()
                    Text(viewModel.contextInfo.isExact ? "точно" : "оценка")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.bar)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.currentReadiness.state {
        case .checking:
            ProgressView()
                .controlSize(.mini)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .requiresSetup:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .unavailable:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var tokenLabel: String {
        "\(viewModel.contextInfo.usedTokens.formatted()) / \(viewModel.contextInfo.contextLimit.formatted()) токенов"
    }

    private var contextColor: Color {
        let ratio = viewModel.contextInfo.usageRatio
        if ratio > 0.85 { return .red }
        if ratio > 0.65 { return .orange }
        return .green
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: conversation.modelType.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(conversation.modelType.shortName)
                    Text("·")
                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
