import SwiftUI

struct ContentView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var showQuickSettings = false
    @State private var showFullInspector = false
    @State private var inspectorSection: InspectorSection = .generation

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } detail: {
            ChatView()
                .navigationTitle(viewModel.selectedConversation?.title ?? "Foundation Chat")
                .inspector(isPresented: $showFullInspector) {
                    SettingsInspectorView(selection: $inspectorSection)
                        .inspectorColumnWidth(min: 350, ideal: 380, max: 460)
                }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.createNewConversation()
                } label: {
                    Label("Новый чат", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .keyboardShortcut("n", modifiers: .command)
                .help("Новый чат (⌘N)")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    if showFullInspector {
                        showFullInspector = false
                    }
                    showQuickSettings.toggle()
                } label: {
                    Label("Параметры", systemImage: "sidebar.trailing")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Быстрые параметры (⌥⌘I)")
                .popover(
                    isPresented: $showQuickSettings,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    QuickSettingsPopover(
                        selection: $inspectorSection,
                        fullInspectorPresented: $showFullInspector,
                        closePopover: {
                            showQuickSettings = false
                        }
                    )
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
    }
}
