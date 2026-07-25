import SwiftUI

struct SidebarView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var conversationPendingDeletion: Conversation?
    @State private var renameConversation: Conversation?
    @State private var renameText = ""
    @State private var showNewProject = false
    @State private var projectName = ""
    @State private var projectPendingRename: ChatFolder?
    @State private var projectPendingDeletion: ChatFolder?
    @State private var expandedProjectIDs: Set<UUID> = []

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return viewModel.conversations }
        return viewModel.conversations.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.messages.contains { $0.content.localizedStandardContains(searchText) }
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                VStack(spacing: 8) {
                    searchField

                    List(selection: $viewModel.selectedConversationID) {
                        pinnedSection
                        projectsSection
                        chatsSection
                    }
                    .listStyle(.sidebar)
                    .overlay { searchEmptyState }
                }
                .padding(.bottom, 45)

                aboutButton
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .alert("Переименовать чат", isPresented: renameConversationBinding) {
            TextField("Название", text: $renameText)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                if let id = renameConversation?.id {
                    viewModel.renameConversation(id, to: renameText)
                }
            }
        }
        .alert("Новый проект", isPresented: $showNewProject) {
            TextField("Название", text: $projectName)
            Button("Отмена", role: .cancel) {}
            Button("Создать") {
                viewModel.createFolder(named: projectName)
            }
        } message: {
            Text("Проект объединяет связанные чаты в боковом меню.")
        }
        .alert("Переименовать проект", isPresented: projectRenameBinding) {
            TextField("Название", text: $projectName)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                if let id = projectPendingRename?.id {
                    viewModel.renameFolder(id, to: projectName)
                }
            }
        }
        .confirmationDialog(
            "Удалить проект «\(projectPendingDeletion?.name ?? "")»?",
            isPresented: projectDeletionBinding
        ) {
            Button("Удалить проект", role: .destructive) {
                if let id = projectPendingDeletion?.id {
                    viewModel.deleteFolder(id)
                }
                projectPendingDeletion = nil
            }
        } message: {
            Text("Чаты останутся и переместятся в раздел «Чаты».")
        }
        .confirmationDialog(
            "Удалить «\(conversationPendingDeletion?.title ?? "")»?",
            isPresented: conversationDeletionBinding
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

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Поиск по чатам", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Очистить поиск")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = filteredConversations.filter(\.isPinned)
        if !pinned.isEmpty {
            Section("Закреплённые") {
                ForEach(pinned) { conversationRow($0) }
            }
        }
    }

    private var projectsSection: some View {
        Section("Проекты") {
            ForEach(viewModel.folders) { project in
                DisclosureGroup(
                    isExpanded: projectExpansionBinding(for: project.id)
                ) {
                    let conversations = filteredConversations.filter {
                        $0.folderID == project.id && !$0.isPinned
                    }
                    if conversations.isEmpty {
                        Text("В проекте пока нет чатов")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(conversations) { conversationRow($0) }
                    }
                } label: {
                    Label(project.name, systemImage: "folder")
                        .lineLimit(1)
                        .contextMenu { projectMenu(for: project) }
                }
                .padding(.leading, 8)
            }

            Button {
                projectName = ""
                showNewProject = true
            } label: {
                Label(
                    viewModel.folders.isEmpty ? "Создать проект" : "Новый проект",
                    systemImage: "folder.badge.plus"
                )
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Проекты объединяют связанные чаты")
        }
    }

    @ViewBuilder
    private var chatsSection: some View {
        let unfiled = filteredConversations.filter {
            $0.folderID == nil && !$0.isPinned
        }
        if !unfiled.isEmpty {
            Section("Чаты") {
                ForEach(unfiled) { conversationRow($0) }
            }
        }
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        if filteredConversations.isEmpty && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if viewModel.conversations.isEmpty {
            ContentUnavailableView {
                Label("Нет чатов", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Создайте первый чат кнопкой выше.")
            }
        }
    }

    private var aboutButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                openWindow(id: "about")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .frame(width: 16)
                    Text("О проекте")
                    Spacer()
                }
                    .contentShape(.rect)
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.vertical, 11)
            .help("Версия, авторы и репозиторий GitHub")
        }
        .frame(maxWidth: .infinity)
        .background(.bar)
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
                Menu("Переместить в проект", systemImage: "folder") {
                    Button("Без проекта") {
                        viewModel.moveConversation(conversation.id, to: nil)
                    }
                    ForEach(viewModel.folders) { project in
                        Button(project.name) {
                            viewModel.moveConversation(conversation.id, to: project.id)
                        }
                    }
                }
                Divider()
                Button("Удалить", systemImage: "trash", role: .destructive) {
                    conversationPendingDeletion = conversation
                }
            }
    }

    @ViewBuilder
    private func projectMenu(for project: ChatFolder) -> some View {
        Button("Переименовать проект", systemImage: "pencil") {
            projectName = project.name
            projectPendingRename = project
        }
        Button("Удалить проект", systemImage: "trash", role: .destructive) {
            projectPendingDeletion = project
        }
    }

    private func projectExpansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedProjectIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedProjectIDs.insert(id)
                } else {
                    expandedProjectIDs.remove(id)
                }
            }
        )
    }

    private var renameConversationBinding: Binding<Bool> {
        Binding(
            get: { renameConversation != nil },
            set: { if !$0 { renameConversation = nil } }
        )
    }

    private var projectRenameBinding: Binding<Bool> {
        Binding(
            get: { projectPendingRename != nil },
            set: { if !$0 { projectPendingRename = nil } }
        )
    }

    private var projectDeletionBinding: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { if !$0 { projectPendingDeletion = nil } }
        )
    }

    private var conversationDeletionBinding: Binding<Bool> {
        Binding(
            get: { conversationPendingDeletion != nil },
            set: { if !$0 { conversationPendingDeletion = nil } }
        )
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
