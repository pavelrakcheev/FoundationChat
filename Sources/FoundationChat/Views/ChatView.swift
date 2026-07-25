import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private var messages: [Message] {
        viewModel.selectedConversation?.messages ?? []
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
            }
            .frame(
                width: geometry.size.width,
                height: max(0, geometry.size.height - 96)
            )
            .position(
                x: geometry.size.width / 2,
                y: max(0, geometry.size.height - 96) / 2
            )

            ComposerView(
                text: $inputText,
                isFocused: $isInputFocused,
                send: send
            )
            .frame(width: geometry.size.width)
            .position(
                x: geometry.size.width / 2,
                y: max(48, geometry.size.height - 48)
            )
            .zIndex(1)
        }
        .onAppear { isInputFocused = true }
        .onChange(of: viewModel.selectedConversationID) { _, _ in
            isInputFocused = true
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(messages) { message in
                        MessageBubbleView(
                            message: message,
                            modelName: viewModel.modelType.shortName
                        )
                        .id(message.id)
                    }
                }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
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

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)

            Image(systemName: "apple.intelligence")
                .font(.system(size: 54, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Foundation Chat")
                    .font(.largeTitle.weight(.semibold))

                Text("Полигон Apple Foundation Models")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            ModelWelcomeCard()

            if !viewModel.currentReadiness.canGenerate {
                Label(
                    viewModel.currentReadiness.detail,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            } else {
                Text("Введите запрос ниже. История и системные инструкции сохраняются локально.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func send() {
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        viewModel.sendMessage(text)
        if viewModel.currentReadiness.canGenerate {
            inputText = ""
        }
    }

    private func scrollToBottom(
        _ proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
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

private struct ModelWelcomeCard: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.modelType.iconName)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.modelType.displayName)
                    .font(.headline)
                Text(viewModel.modelType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: 480, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct ComposerView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let send: () -> Void

    private var canSend: Bool {
        viewModel.currentReadiness.canGenerate
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isProcessing
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
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

                if viewModel.isProcessing {
                    Button {
                        viewModel.cancelGeneration()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .buttonBorderShape(.circle)
                    .help("Остановить генерацию (⌘.)")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!canSend)
                    .help("Отправить")
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.currentReadiness.canGenerate ? .green : .orange)
                    .frame(width: 6, height: 6)
                Text(viewModel.modelType.displayName)

                Spacer()

                Text(
                    "\(viewModel.contextInfo.usedTokens.formatted()) / \(viewModel.contextInfo.contextLimit.formatted())"
                )
                Text("токенов")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: 22)
        )
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(minHeight: 82)
        .fixedSize(horizontal: false, vertical: true)
    }
}
