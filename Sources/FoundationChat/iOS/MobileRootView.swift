#if os(iOS)
import SwiftUI

private enum MobileSheet: String, Identifiable {
    case settings
    case about

    var id: String { rawValue }
}

struct MobileRootView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var presentedSheet: MobileSheet?
    @State private var intentRouter = AppIntentRouter.shared
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
        NavigationStack(path: $path) {
            List {
                localModelSection
                emptyStateSection
                pinnedSection
                projectSection
                chatsSection
                aboutSection
            }
            .navigationTitle("Foundation Chat")
            .searchable(text: $searchText, prompt: "Поиск по чатам")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createChat) {
                        Label("Новый чат", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { conversationID in
                MobileChatView(conversationID: conversationID)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .settings:
                MobileSettingsView()
                    .environment(viewModel)
            case .about:
                MobileAboutView()
            }
        }
        .alert(
            "Не удалось выполнить запрос",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Новый проект", isPresented: $showNewProject) {
            TextField("Название", text: $projectName)
            Button("Отмена", role: .cancel) {}
            Button("Создать") {
                if let id = viewModel.createFolder(named: projectName) {
                    expandedProjectIDs.insert(id)
                }
                projectName = ""
            }
        } message: {
            Text("Проект объединяет связанные чаты.")
        }
        .alert("Переименовать проект", isPresented: projectRenameBinding) {
            TextField("Название", text: $projectName)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                if let id = projectPendingRename?.id {
                    viewModel.renameFolder(id, to: projectName)
                }
                projectPendingRename = nil
            }
        }
        .confirmationDialog(
            "Удалить проект «\(projectPendingDeletion?.name ?? "")»?",
            isPresented: projectDeletionBinding
        ) {
            Button("Удалить проект", role: .destructive) {
                if let id = projectPendingDeletion?.id {
                    viewModel.deleteFolder(id)
                    expandedProjectIDs.remove(id)
                }
                projectPendingDeletion = nil
            }
        } message: {
            Text("Чаты останутся и переместятся в раздел «Чаты».")
        }
        .onAppear { handleIntent(intentRouter.request) }
        .onChange(of: intentRouter.request) { _, request in handleIntent(request) }
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        if viewModel.conversations.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Нет чатов", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Создайте чат и запустите Apple Foundation Model на \(MobilePlatform.deviceName).")
                } actions: {
                    Button("Новый чат", action: createChat)
                        .buttonStyle(.glassProminent)
                }
                .listRowBackground(Color.clear)
            }
        } else if filteredConversations.isEmpty {
            Section {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var localModelSection: some View {
        Section {
            Button {
                presentedSheet = .settings
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Intelligence · Local")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(viewModel.readiness[.local]?.detail ?? "Проверяем модель…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()
                    readinessIcon
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } header: {
            Text("На этом \(MobilePlatform.deviceName)")
        } footer: {
            Text("Запросы Local обрабатываются системной моделью на устройстве и могут работать офлайн.")
        }
    }

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = filteredConversations.filter(\.isPinned)
        if !pinned.isEmpty {
            Section("Закреплённые") {
                ForEach(pinned, content: conversationRow)
            }
        }
    }

    @ViewBuilder
    private var chatsSection: some View {
        let regular = filteredConversations.filter { !$0.isPinned && $0.folderID == nil }
        if !regular.isEmpty {
            Section("Чаты") {
                ForEach(regular, content: conversationRow)
            }
        }
    }

    private var projectSection: some View {
        Section("Проекты") {
            ForEach(viewModel.folders) { project in
                DisclosureGroup(isExpanded: projectExpansionBinding(for: project.id)) {
                    let chats = filteredConversations.filter {
                        $0.folderID == project.id && !$0.isPinned
                    }
                    if chats.isEmpty {
                        Text("В проекте пока нет чатов")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(chats, content: conversationRow)
                    }
                } label: {
                    Label(project.name, systemImage: "folder")
                        .lineLimit(1)
                        .contextMenu {
                            Button("Переименовать", systemImage: "pencil") {
                                projectName = project.name
                                projectPendingRename = project
                            }
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                projectPendingDeletion = project
                            }
                        }
                }
            }

            Button {
                projectName = ""
                showNewProject = true
            } label: {
                Label(
                    viewModel.folders.isEmpty ? "Создать проект" : "Новый проект",
                    systemImage: "folder.badge.plus"
                )
            }
        }
    }

    private var aboutSection: some View {
        Section {
            Button {
                presentedSheet = .settings
            } label: {
                Label("Параметры", systemImage: "slider.horizontal.3")
            }
            Button {
                presentedSheet = .about
            } label: {
                Label("О проекте", systemImage: "info.circle")
            }
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            open(conversation.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(conversation.modelType.shortName)
                    if let last = conversation.messages.last {
                        Text("·")
                        Text(last.content)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
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
                        expandedProjectIDs.insert(project.id)
                    }
                }
            }

            Button("Удалить", systemImage: "trash", role: .destructive) {
                viewModel.deleteConversation(conversation.id)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteConversation(conversation.id)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            Button {
                viewModel.togglePinned(conversation.id)
            } label: {
                Label(
                    conversation.isPinned ? "Открепить" : "Закрепить",
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                )
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private var readinessIcon: some View {
        switch viewModel.readiness[.local]?.state {
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .requiresSetup:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .unavailable:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        default:
            ProgressView().controlSize(.small)
        }
    }

    private func createChat() {
        let id = viewModel.createNewConversation()
        path.append(id)
    }

    private func open(_ id: UUID) {
        viewModel.selectedConversationID = id
        path.append(id)
    }

    private func handleIntent(_ request: AppIntentRouter.Request?) {
        guard let request else { return }
        switch request.action {
        case .newChat(let prompt, let model):
            viewModel.selectModel(model)
            let id = viewModel.createNewConversation()
            path.append(id)
            if let prompt, !prompt.isEmpty {
                viewModel.sendMessage(prompt)
            }
        case .openChat(let id):
            if viewModel.conversations.contains(where: { $0.id == id }) {
                open(id)
            }
        }
        intentRouter.request = nil
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
}
#endif
