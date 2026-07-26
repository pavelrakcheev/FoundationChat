#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct MobileChatView: View {
    @Environment(ChatViewModel.self) private var viewModel
    let conversationID: UUID
    @State private var inputText = ""
    @State private var isImporting = false
    @State private var isShowingSettings = false
    @FocusState private var isComposerFocused: Bool

    private var messages: [Message] {
        viewModel.conversations.first(where: { $0.id == conversationID })?.messages ?? []
    }

    private var title: String {
        viewModel.conversations.first(where: { $0.id == conversationID })?.title ?? "Новый чат"
    }

    var body: some View {
        Group {
            if messages.isEmpty {
                MobileWelcomeView(chooseSuggestion: {
                    inputText = $0
                    isComposerFocused = true
                })
            } else {
                messageList
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MobileComposerView(
                text: $inputText,
                isFocused: $isComposerFocused,
                chooseFiles: { isImporting = true },
                send: send
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Параметры", systemImage: "slider.horizontal.3")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .pdf, .plainText, .json, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.importAttachments(urls)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            MobileSettingsView()
                .environment(viewModel)
        }
        .onAppear {
            viewModel.selectedConversationID = conversationID
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(messages) { message in
                        MobileMessageView(message: message, onQuote: quote)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
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
        let value = inputText
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty else { return }
        viewModel.sendMessage(value, attachments: attachments)
        inputText = ""
    }

    private func quote(_ value: String) {
        let quote = value.components(separatedBy: .newlines)
            .map { "> \($0)" }
            .joined(separator: "\n")
        inputText = "\(quote)\n\nУточни этот фрагмент: "
        isComposerFocused = true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let id = messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

private struct MobileWelcomeView: View {
    let chooseSuggestion: (String) -> Void

    private let suggestions = MobileWelcomeSuggestion.all

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .padding(.top, 36)

                VStack(spacing: 6) {
                    Text("Что попробуем?")
                        .font(.title.bold())
                    Text("Apple Foundation Model работает прямо на \(MobilePlatform.deviceName).")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            chooseSuggestion(suggestion.prompt)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: suggestion.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(height: 24)

                                Text(suggestion.title)
                                    .font(.headline)
                                    .multilineTextAlignment(.leading)

                                Text(suggestion.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(4)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)

                                HStack(spacing: 6) {
                                    Text(suggestion.badge)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)
                            .padding(14)
                            .background(.quinary, in: .rect(cornerRadius: 18))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 120)
        }
    }
}

private struct MobileWelcomeSuggestion: Identifiable {
    let id: String
    let title: String
    let explanation: String
    let badge: String
    let systemImage: String
    let prompt: String

    static let all = [
        MobileWelcomeSuggestion(
            id: "summarize",
            title: "Разобрать документ",
            explanation: "Получить краткое резюме, решения, сроки и следующие шаги.",
            badge: "Текст и файлы",
            systemImage: "doc.text.magnifyingglass",
            prompt: "Кратко резюмируй документ. Выдели решения, сроки, риски и следующие шаги."
        ),
        MobileWelcomeSuggestion(
            id: "vision",
            title: "Понять изображение",
            explanation: "Описать сцену, прочитать текст или объяснить диаграмму.",
            badge: "Vision · OCR",
            systemImage: "photo.badge.magnifyingglass",
            prompt: "Проанализируй изображение: опиши главное, прочитай текст и отметь важные детали."
        ),
        MobileWelcomeSuggestion(
            id: "structure",
            title: "Структурировать данные",
            explanation: "Превратить свободный текст в пункты, таблицу или проверяемый JSON.",
            badge: "Guided generation",
            systemImage: "curlybraces.square",
            prompt: "Преобразуй данные в чёткую структуру: резюме, категории, факты и действия."
        ),
        MobileWelcomeSuggestion(
            id: "rewrite",
            title: "Улучшить текст",
            explanation: "Переписать письмо или заметку яснее, короче и в нужном тоне.",
            badge: "Локально",
            systemImage: "text.badge.checkmark",
            prompt: "Перепиши текст яснее и короче. Дай нейтральную и дружелюбную версии."
        )
    ]
}
#endif
