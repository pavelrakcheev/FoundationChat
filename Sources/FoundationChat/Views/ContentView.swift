import SwiftUI

struct ContentView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
        } detail: {
            ChatView()
                .navigationTitle(viewModel.selectedConversation?.title ?? "Foundation Chat")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.createNewConversation()
                } label: {
                    Label("Новый чат", systemImage: "square.and.pencil")
                }
                .help("Новый чат (⌘N)")
            }

            ToolbarSpacer(.fixed)

            ToolbarItem {
                Menu {
                    ForEach(ModelType.allCases) { type in
                        Button {
                            viewModel.selectModel(type)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(type.displayName)
                                    Text(type.description)
                                }
                            } icon: {
                                Image(systemName: type.iconName)
                            }
                        }
                    }
                } label: {
                    Label(
                        viewModel.modelType.shortName,
                        systemImage: viewModel.modelType.iconName
                    )
                }
                .disabled(viewModel.isProcessing)
                .help("Выбрать модель")
            }

            ToolbarItem {
                Menu {
                    Button("Очистить текущий чат", systemImage: "eraser") {
                        showClearConfirmation = true
                    }
                    .disabled(viewModel.selectedConversation == nil)

                    Divider()

                    SettingsLink {
                        Label("Настройки…", systemImage: "gearshape")
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
