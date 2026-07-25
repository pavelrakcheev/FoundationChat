import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var inputText = ""
    @State private var intentRouter = AppIntentRouter.shared
    @FocusState private var isInputFocused: Bool

    private var messages: [Message] {
        viewModel.selectedConversation?.messages ?? []
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Group {
                    if messages.isEmpty {
                        WelcomeView(
                            modelType: viewModel.modelType,
                            readiness: viewModel.currentReadiness,
                            chooseSuggestion: chooseSuggestion
                        )
                    } else {
                        messageList
                    }
                }
                .padding(.bottom, 82)

                ComposerView(
                    text: $inputText,
                    isFocused: $isInputFocused,
                    send: send
                )
                .fixedSize(horizontal: false, vertical: true)
                .background(.bar)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.importAttachments(urls)
            return !urls.isEmpty
        }
        .onAppear {
            isInputFocused = true
            handleIntent(intentRouter.request)
        }
        .onChange(of: viewModel.selectedConversationID) { _, _ in
            isInputFocused = true
        }
        .onChange(of: intentRouter.request) { _, request in
            handleIntent(request)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(messages) { message in
                        MessageBubbleView(
                            message: message,
                            modelName: viewModel.modelType.shortName,
                            onQuote: quote
                        )
                        .id(message.id)
                    }
                }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: messages.last?.content.count ?? 0) { _, _ in
                if viewModel.isProcessing {
                    scrollToBottom(proxy, animated: false)
                }
            }
        }
    }

    private func send() {
        guard viewModel.currentReadiness.canGenerate, !viewModel.isProcessing else { return }
        let attachments = viewModel.consumePendingAttachments()
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty else { return }
        viewModel.sendMessage(text, attachments: attachments)
        if viewModel.currentReadiness.canGenerate {
            inputText = ""
        }
    }

    private func quote(_ selectedText: String) {
        let value = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let quotation = value
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
            .joined(separator: "\n")
        inputText = inputText.isEmpty
            ? "\(quotation)\n\nУточни этот фрагмент: "
            : "\(inputText)\n\n\(quotation)\n\n"
        isInputFocused = true
    }

    private func chooseSuggestion(_ prompt: String) {
        inputText = prompt
        isInputFocused = true
    }

    private func handleIntent(_ request: AppIntentRouter.Request?) {
        guard let request else { return }
        switch request.action {
        case .newChat(let prompt, let model):
            viewModel.selectModel(model)
            viewModel.createNewConversation()
            inputText = prompt ?? ""
            isInputFocused = true
        case .openChat(let id):
            if viewModel.conversations.contains(where: { $0.id == id }) {
                viewModel.selectedConversationID = id
            }
        }
        intentRouter.request = nil
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastID = messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}
