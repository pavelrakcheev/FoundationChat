import AppKit
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
            Group {
                if messages.isEmpty { emptyState } else { messageList }
            }
            .frame(width: geometry.size.width, height: max(0, geometry.size.height - 112))
            .position(
                x: geometry.size.width / 2,
                y: max(0, geometry.size.height - 112) / 2
            )

            ComposerView(
                text: $inputText,
                isFocused: $isInputFocused,
                send: send,
                quote: quote
            )
            .frame(width: geometry.size.width)
            .position(
                x: geometry.size.width / 2,
                y: max(56, geometry.size.height - 56)
            )
            .zIndex(1)
        }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.importAttachments(urls)
            return !urls.isEmpty
        }
        .onAppear { isInputFocused = true }
        .onChange(of: viewModel.selectedConversationID) { _, _ in
            isInputFocused = true
        }
        .onChange(of: intentRouter.request) { _, request in
            handleIntent(request)
        }
        .onAppear { handleIntent(intentRouter.request) }
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
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: messages.last?.content.count ?? 0) { _, _ in
                if viewModel.isProcessing { scrollToBottom(proxy, animated: false) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            Image(systemName: "apple.intelligence")
                .font(.system(size: 52, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(spacing: 7) {
                Text("Foundation Chat").font(.largeTitle.weight(.semibold))
                Text("Полигон Apple Foundation Models")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label(viewModel.modelType.fullName, systemImage: viewModel.modelType.iconName)
                Text("·").foregroundStyle(.tertiary)
                Text(viewModel.currentReadiness.detail)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            Text("Перетащите изображение или файл в окно либо начните обычный чат.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func send() {
        guard viewModel.currentReadiness.canGenerate, !viewModel.isProcessing else { return }
        let attachments = viewModel.consumePendingAttachments()
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty else { return }
        viewModel.sendMessage(text, attachments: attachments)
        if viewModel.currentReadiness.canGenerate { inputText = "" }
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

private struct ComposerView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let send: () -> Void
    let quote: (String) -> Void

    private var canSend: Bool {
        viewModel.currentReadiness.canGenerate
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !viewModel.pendingAttachments.isEmpty)
            && !viewModel.isProcessing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.pendingAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(viewModel.pendingAttachments) { attachment in
                            HStack(spacing: 5) {
                                Image(systemName: attachment.kind == .image ? "photo" : "doc")
                                Text(attachment.name).lineLimit(1)
                                Button {
                                    viewModel.removePendingAttachment(attachment.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.quinary, in: .capsule)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button(action: chooseFiles) {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(viewModel.isProcessing)
                .help("Прикрепить файл или изображение")

                TextField(
                    "Сообщение для \(viewModel.modelType.shortName)",
                    text: $text,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .focused(isFocused)
                .lineLimit(1...7)
                .onSubmit(send)
                .disabled(viewModel.isProcessing)

                Menu {
                    ForEach(ModelType.allCases) { type in
                        Button {
                            viewModel.selectModel(type)
                        } label: {
                            if viewModel.modelType == type {
                                Label(type.shortName, systemImage: "checkmark")
                            } else {
                                Text(type.shortName)
                            }
                        }
                    }
                } label: {
                    Label(viewModel.modelType.shortName, systemImage: viewModel.modelType.iconName)
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(viewModel.isProcessing)

                if viewModel.isProcessing {
                    Button { viewModel.cancelGeneration() } label: {
                        Image(systemName: "stop.fill").frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .buttonBorderShape(.circle)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up").frame(width: 18, height: 18)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!canSend)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Прикрепить"
        if panel.runModal() == .OK {
            viewModel.importAttachments(panel.urls)
        }
    }
}
