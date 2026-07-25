import SwiftUI

@main
struct FoundationChatApp: App {
    @State private var viewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 900, minHeight: 580)
                .task { await viewModel.checkAvailability() }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новый чат") {
                    viewModel.createNewConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Чат") {
                Button("Очистить текущий чат") {
                    viewModel.clearCurrentConversation()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(viewModel.selectedConversation == nil)

                Button("Остановить генерацию") {
                    viewModel.cancelGeneration()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!viewModel.isProcessing)
            }

            CommandMenu("Модель") {
                ForEach(ModelType.allCases) { type in
                    Button {
                        viewModel.selectModel(type)
                    } label: {
                        if viewModel.modelType == type {
                            Label(type.displayName, systemImage: "checkmark")
                        } else {
                            Text(type.displayName)
                        }
                    }
                    .disabled(viewModel.isProcessing)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}
