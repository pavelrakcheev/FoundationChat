import SwiftUI

struct SidebarView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var searchText = ""
    @State private var conversationPendingDeletion: Conversation?
    @State private var renameConversation: Conversation?
    @State private var renameText = ""
    @State private var showNewFolder = false
    @State private var folderName = ""
    @State private var folderPendingRename: ChatFolder?
    @State private var folderPendingDeletion: ChatFolder?

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return viewModel.conversations }
        return viewModel.conversations.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.messages.contains { $0.content.localizedStandardContains(searchText) }
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    viewModel.createNewConversation()
                } label: {
                    Label("Новый чат", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    folderName = ""
                    showNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.glass)
                .help("Новая папка")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            List(selection: $viewModel.selectedConversationID) {
                let pinned = filteredConversations.filter(\.isPinned)
                if !pinned.isEmpty {
                    Section("Закреплённые") {
                        ForEach(pinned) { conversationRow($0) }
                    }
                }

                ForEach(viewModel.folders) { folder in
                    Section {
                        ForEach(filteredConversations.filter { $0.folderID == folder.id && !$0.isPinned }) {
                            conversationRow($0)
                        }
                    } header: {
                        HStack {
                            Text(folder.name)
                            Spacer()
                            Menu {
                                Button("Переименовать", systemImage: "pencil") {
                                    folderName = folder.name
                                    folderPendingRename = folder
                                }
                                Button("Удалить папку", systemImage: "trash", role: .destructive) {
                                    folderPendingDeletion = folder
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                }

                let unfiled = filteredConversations.filter {
                    $0.folderID == nil && !$0.isPinned
                }
                if !unfiled.isEmpty {
                    Section("Чаты") {
                        ForEach(unfiled) { conversationRow($0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Поиск")
            .overlay {
                if filteredConversations.isEmpty {
                    ContentUnavailableView {
                        Label(
                            searchText.isEmpty ? "Нет чатов" : "Ничего не найдено",
                            systemImage: searchText.isEmpty
                                ? "bubble.left.and.bubble.right" : "magnifyingglass"
                        )
                    } description: {
                        if searchText.isEmpty { Text("Создайте первый чат.") }
                    }
                }
            }
        }
        .alert("Переименовать чат", isPresented: Binding(
            get: { renameConversation != nil },
            set: { if !$0 { renameConversation = nil } }
        )) {
            TextField("Название", text: $renameText)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                if let id = renameConversation?.id {
                    viewModel.renameConversation(id, to: renameText)
                }
            }
        }
        .alert("Новая папка", isPresented: $showNewFolder) {
            TextField("Название", text: $folderName)
            Button("Отмена", role: .cancel) {}
            Button("Создать") { viewModel.createFolder(named: folderName) }
        }
        .alert("Переименовать папку", isPresented: Binding(
            get: { folderPendingRename != nil },
            set: { if !$0 { folderPendingRename = nil } }
        )) {
            TextField("Название", text: $folderName)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                if let id = folderPendingRename?.id {
                    viewModel.renameFolder(id, to: folderName)
                }
            }
        }
        .confirmationDialog(
            "Удалить папку «\(folderPendingDeletion?.name ?? "")»?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            )
        ) {
            Button("Удалить папку", role: .destructive) {
                if let id = folderPendingDeletion?.id { viewModel.deleteFolder(id) }
                folderPendingDeletion = nil
            }
        } message: {
            Text("Чаты останутся и переместятся в раздел «Чаты».")
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

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        ConversationRow(conversation: conversation)
            .tag(conversation.id)
            .contextMenu {
                Button("Переименовать", systemImage: "pencil") {
                    renameText = conversation.title
                    renameConversation = conversation
                }
                Button(
                    conversation.isPinned ? "Открепить" : "Закрепить",
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                ) {
                    viewModel.togglePinned(conversation.id)
                }
                Menu("Переместить", systemImage: "folder") {
                    Button("Без папки") {
                        viewModel.moveConversation(conversation.id, to: nil)
                    }
                    ForEach(viewModel.folders) { folder in
                        Button(folder.name) {
                            viewModel.moveConversation(conversation.id, to: folder.id)
                        }
                    }
                }
                Divider()
                Button("Удалить", systemImage: "trash", role: .destructive) {
                    conversationPendingDeletion = conversation
                }
            }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(conversation.modelType.shortName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
