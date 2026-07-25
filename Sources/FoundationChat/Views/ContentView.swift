import SwiftUI

struct ContentView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @State private var showInspector = true
    @State private var inspectorSection: InspectorSection = .generation
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            ChatView()
                .navigationTitle(viewModel.selectedConversation?.title ?? "Foundation Chat")
                .inspector(isPresented: $showInspector) {
                    SettingsInspectorView(selection: $inspectorSection)
                        .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
                }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Параметры", systemImage: "sidebar.trailing")
                }
                .help("Показать или скрыть параметры (⌥⌘I)")
            }

            ToolbarItem {
                Menu {
                    Button("Очистить текущий чат", systemImage: "eraser") {
                        showClearConfirmation = true
                    }
                    .disabled(viewModel.selectedConversation == nil)
                    Divider()
                    Button("О проекте", systemImage: "info.circle") {
                        openWindow(id: "about")
                    }
                } label: {
                    Label("Действия", systemImage: "ellipsis")
                }
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
        .confirmationDialog(
            "Очистить текущий чат?",
            isPresented: $showClearConfirmation
        ) {
            Button("Очистить", role: .destructive) {
                viewModel.clearCurrentConversation()
            }
        } message: {
            Text("Сообщения будут удалены без возможности восстановления.")
        }
    }
}
