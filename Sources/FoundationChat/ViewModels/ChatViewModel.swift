import Foundation
import FoundationModels
import SwiftUI

@MainActor
@Observable
final class ChatViewModel {
    var conversations: [Conversation]
    var selectedConversationID: UUID? {
        didSet {
            syncModelWithSelectedConversation()
            updateContextInfo()
            persist()
        }
    }
    private(set) var isProcessing = false
    private(set) var modelType: ModelType
    private(set) var readiness: [ModelType: ModelReadiness]
    var errorMessage: String?
    var settings: GenerationSettings {
        didSet {
            if oldValue.systemInstructions != settings.systemInstructions {
                sessions.removeAll()
                usageByConversation.removeAll()
                updateContextInfo()
            }
            persist()
        }
    }
    private(set) var contextInfo: ContextInfo = .empty

    var selectedConversation: Conversation? {
        guard let id = selectedConversationID else { return nil }
        return conversations.first { $0.id == id }
    }

    var currentReadiness: ModelReadiness {
        readiness[modelType] ?? .checking(for: modelType)
    }

    private struct SessionRecord {
        let session: LanguageModelSession
        let modelType: ModelType
        let instructions: String

        func matches(
            modelType: ModelType,
            instructions: String
        ) -> Bool {
            self.modelType == modelType
                && self.instructions == instructions
        }
    }

    private var sessions: [UUID: SessionRecord] = [:]
    private var usageByConversation: [UUID: ContextInfo] = [:]
    private var currentTask: Task<Void, Never>?
    private var generationConversationID: UUID?
    private let service = ModelService()
    private let store: AppStateStore

    init(store: AppStateStore = AppStateStore()) {
        self.store = store

        if let saved = store.load() {
            conversations = saved.conversations.sorted { $0.updatedAt > $1.updatedAt }
            selectedConversationID = saved.selectedConversationID
            modelType = saved.selectedModel
            settings = saved.settings
        } else {
            conversations = []
            selectedConversationID = nil
            modelType = .systemOnDevice
            settings = GenerationSettings()
        }

        readiness = Dictionary(
            uniqueKeysWithValues: ModelType.allCases.map { ($0, .checking(for: $0)) }
        )

        if selectedConversation == nil {
            selectedConversationID = conversations.first?.id
        }
        syncModelWithSelectedConversation()
        updateContextInfo()
    }

    func checkAvailability() async {
        for type in ModelType.allCases {
            readiness[type] = await service.readiness(for: type)
        }
        updateContextInfo()
    }

    func refreshAvailability(for type: ModelType) async {
        readiness[type] = .checking(for: type)
        readiness[type] = await service.readiness(for: type)
        updateContextInfo()
    }

    func selectModel(_ type: ModelType) {
        guard modelType != type, !isProcessing else { return }
        modelType = type
        errorMessage = nil

        if let index = selectedConversationIndex {
            conversations[index].modelType = type
            conversations[index].updatedAt = Date()
            sessions.removeValue(forKey: conversations[index].id)
            usageByConversation.removeValue(forKey: conversations[index].id)
            sortConversationsKeepingSelection()
        }

        updateContextInfo()
        persist()

        Task { await refreshAvailability(for: type) }
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isProcessing else { return }

        guard currentReadiness.canGenerate else {
            errorMessage = currentReadiness.detail
            return
        }

        let conversationID = ensureConversation()
        let type = modelType
        let settingsSnapshot = settings
        let existingHistory = messages(in: conversationID)

        currentTask = Task { [weak self] in
            guard let self else { return }

            isProcessing = true
            generationConversationID = conversationID
            errorMessage = nil

            let assistantID = UUID()
            var producedContent = false

            defer {
                if generationConversationID == conversationID {
                    isProcessing = false
                    generationConversationID = nil
                    currentTask = nil
                }
                updateContextInfo()
                persist()
            }

            do {
                let session = try await session(
                    for: conversationID,
                    type: type,
                    settings: settingsSnapshot,
                    history: existingHistory
                )

                appendMessage(
                    Message(role: .user, content: trimmed),
                    to: conversationID
                )
                appendMessage(
                    Message(id: assistantID, role: .assistant, content: ""),
                    to: conversationID
                )
                updateConversationTitleIfNeeded(
                    conversationID: conversationID,
                    userText: trimmed
                )
                sortConversationsKeepingSelection()
                persist()

                let options = GenerationOptions(
                    temperature: settingsSnapshot.temperature,
                    maximumResponseTokens: settingsSnapshot.useMaxTokens
                        ? settingsSnapshot.maxTokens
                        : nil
                )
                let contextOptions = ContextOptions(
                    reasoningLevel: reasoningLevel(
                        for: type,
                        setting: settingsSnapshot.reasoningLevel
                    )
                )

                let stream = session.streamResponse(
                    to: trimmed,
                    options: options,
                    contextOptions: contextOptions
                )

                for try await snapshot in stream {
                    guard !Task.isCancelled else { break }
                    producedContent = !snapshot.content.isEmpty
                    updateMessage(
                        assistantID,
                        in: conversationID,
                        content: snapshot.content
                    )
                    applyUsage(
                        snapshot.usage,
                        modelType: type,
                        conversationID: conversationID
                    )
                }

                if Task.isCancelled {
                    sessions.removeValue(forKey: conversationID)
                    usageByConversation.removeValue(forKey: conversationID)
                    if producedContent {
                        appendInterruptionNote(to: assistantID, in: conversationID)
                    } else {
                        removeMessage(assistantID, from: conversationID)
                    }
                }
            } catch {
                sessions.removeValue(forKey: conversationID)
                usageByConversation.removeValue(forKey: conversationID)

                if !Task.isCancelled {
                    if !hasMessage(assistantID, in: conversationID) {
                        appendMessage(
                            Message(role: .user, content: trimmed),
                            to: conversationID
                        )
                        updateConversationTitleIfNeeded(
                            conversationID: conversationID,
                            userText: trimmed
                        )
                        sortConversationsKeepingSelection()
                    } else {
                        removeMessage(assistantID, from: conversationID)
                    }

                    appendMessage(
                        Message(role: .error, content: describe(error)),
                        to: conversationID
                    )
                    await refreshAvailability(for: type)
                }
            }
        }
    }

    func cancelGeneration() {
        currentTask?.cancel()
    }

    @discardableResult
    func createNewConversation() -> UUID {
        let conversation = Conversation(modelType: modelType)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        updateContextInfo()
        persist()
        return conversation.id
    }

    func deleteConversation(_ id: UUID) {
        if generationConversationID == id {
            cancelGeneration()
        }

        sessions.removeValue(forKey: id)
        usageByConversation.removeValue(forKey: id)
        let deletedIndex = conversations.firstIndex { $0.id == id }
        conversations.removeAll { $0.id == id }

        if selectedConversationID == id {
            if let deletedIndex, !conversations.isEmpty {
                selectedConversationID = conversations[min(deletedIndex, conversations.count - 1)].id
            } else {
                selectedConversationID = conversations.first?.id
            }
        }

        updateContextInfo()
        persist()
    }

    func clearCurrentConversation() {
        guard let index = selectedConversationIndex else { return }
        let id = conversations[index].id

        if generationConversationID == id {
            cancelGeneration()
        }

        conversations[index].messages.removeAll()
        conversations[index].title = "Новый чат"
        conversations[index].updatedAt = Date()
        sessions.removeValue(forKey: id)
        usageByConversation.removeValue(forKey: id)
        updateContextInfo()
        persist()
    }

    func resetInstructions() {
        settings.systemInstructions = GenerationSettings.defaultInstructions
    }

    func dismissError() {
        errorMessage = nil
    }

    private var selectedConversationIndex: Int? {
        guard let id = selectedConversationID else { return nil }
        return conversations.firstIndex { $0.id == id }
    }

    private func ensureConversation() -> UUID {
        if let selectedConversationID {
            return selectedConversationID
        }
        return createNewConversation()
    }

    private func session(
        for conversationID: UUID,
        type: ModelType,
        settings: GenerationSettings,
        history: [Message]
    ) async throws -> LanguageModelSession {
        if let record = sessions[conversationID],
           record.matches(
               modelType: type,
               instructions: settings.systemInstructions
           ) {
            return record.session
        }

        let session = try await service.makeSession(
            type: type,
            instructions: settings.systemInstructions,
            history: history
        )
        sessions[conversationID] = SessionRecord(
            session: session,
            modelType: type,
            instructions: settings.systemInstructions
        )
        return session
    }

    private func reasoningLevel(
        for type: ModelType,
        setting: GenerationSettings.ReasoningLevel
    ) -> ContextOptions.ReasoningLevel? {
        guard type.supportsReasoning else { return nil }

        switch setting {
        case .none:
            return nil
        case .light:
            return .light
        case .moderate:
            return .moderate
        case .deep:
            return .deep
        }
    }

    private func messages(in conversationID: UUID) -> [Message] {
        conversations.first { $0.id == conversationID }?.messages ?? []
    }

    private func appendMessage(_ message: Message, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
    }

    private func updateMessage(
        _ messageID: UUID,
        in conversationID: UUID,
        content: String
    ) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
                  $0.id == messageID
              })
        else {
            return
        }

        conversations[conversationIndex].messages[messageIndex].content = content
        conversations[conversationIndex].updatedAt = Date()
    }

    private func removeMessage(_ messageID: UUID, from conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        conversations[index].messages.removeAll { $0.id == messageID }
        conversations[index].updatedAt = Date()
    }

    private func hasMessage(_ messageID: UUID, in conversationID: UUID) -> Bool {
        messages(in: conversationID).contains { $0.id == messageID }
    }

    private func appendInterruptionNote(to messageID: UUID, in conversationID: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
                  $0.id == messageID
              })
        else {
            return
        }

        conversations[conversationIndex].messages[messageIndex].content +=
            "\n\n*Генерация остановлена пользователем.*"
    }

    private func updateConversationTitleIfNeeded(
        conversationID: UUID,
        userText: String
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              conversations[index].title == "Новый чат"
        else {
            return
        }

        let firstLine = userText
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = String(firstLine.prefix(52))
        if !title.isEmpty {
            conversations[index].title = title
        }
    }

    private func syncModelWithSelectedConversation() {
        guard let conversation = selectedConversation else { return }
        modelType = conversation.modelType
    }

    private func sortConversationsKeepingSelection() {
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    private func applyUsage(
        _ usage: LanguageModelSession.Usage,
        modelType: ModelType,
        conversationID: UUID
    ) {
        let info = ContextInfo(
            modelName: modelType.displayName,
            contextLimit: readiness[modelType]?.contextLimit
                ?? modelType.fallbackContextLimit,
            inputTokens: usage.input.totalTokenCount,
            outputTokens: usage.output.totalTokenCount,
            cachedTokens: usage.input.cachedTokenCount,
            reasoningTokens: usage.output.reasoningTokenCount,
            isExact: true
        )
        usageByConversation[conversationID] = info
        if selectedConversationID == conversationID {
            contextInfo = info
        }
    }

    private func updateContextInfo() {
        let limit = readiness[modelType]?.contextLimit
            ?? modelType.fallbackContextLimit
        let text = selectedConversation?.messages
            .filter { $0.role != .error }
            .map(\.content)
            .joined(separator: "\n") ?? ""
        let estimated = max(0, (text.count + settings.systemInstructions.count) / 4)

        if let selectedConversationID,
           sessions[selectedConversationID] != nil,
           var exactUsage = usageByConversation[selectedConversationID],
           exactUsage.modelName == modelType.displayName {
            exactUsage.contextLimit = limit
            contextInfo = exactUsage
        } else {
            contextInfo = ContextInfo(
                modelName: modelType.displayName,
                contextLimit: limit,
                inputTokens: estimated,
                outputTokens: 0,
                cachedTokens: 0,
                reasoningTokens: 0,
                isExact: false
            )
        }
    }

    private func describe(_ error: Error) -> String {
        if let error = error as? PrivateCloudComputeLanguageModel.Error {
            switch error {
            case .networkFailure(let detail):
                return "Private Cloud Compute: ошибка сети.\n\n\(detail.debugDescription)"
            case .quotaLimitReached(let detail):
                if let resetDate = detail.resetDate {
                    return "Лимит Private Cloud Compute исчерпан. Сброс: \(resetDate.formatted())."
                }
                return "Лимит Private Cloud Compute исчерпан."
            case .serviceUnavailable(let detail):
                return "Сервис Private Cloud Compute временно недоступен.\n\n\(detail.debugDescription)"
            @unknown default:
                return "Private Cloud Compute вернул неизвестную ошибку: \(error.localizedDescription)"
            }
        }

        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded(let detail):
                return "Контекст переполнен: \(detail.tokenCount) из \(detail.contextSize) токенов. Сократите историю или начните новый чат."
            case .rateLimited(let detail):
                if let resetDate = detail.resetDate {
                    return "Слишком много запросов. Повторите после \(resetDate.formatted())."
                }
                return "Слишком много запросов. Повторите немного позже."
            case .guardrailViolation:
                return "Ответ остановлен системными ограничениями безопасности модели."
            case .refusal:
                return "Модель отказалась выполнить этот запрос."
            case .unsupportedCapability:
                return "Выбранная модель не поддерживает запрошенную возможность."
            case .unsupportedTranscriptContent:
                return "Модель не поддерживает один из элементов истории чата."
            case .unsupportedGenerationGuide:
                return "Модель не поддерживает выбранный формат генерации."
            case .unsupportedLanguageOrLocale:
                return "Модель не поддерживает язык или регион этого запроса."
            case .timeout:
                return "Модель не успела ответить. Повторите запрос."
            @unknown default:
                return "Foundation Models вернул неизвестную ошибку: \(error.localizedDescription)"
            }
        }

        if let error = error as? LanguageModelSession.Error {
            switch error {
            case .concurrentRequests:
                return "Сессия уже обрабатывает другой запрос."
            case .transcriptMutationWhileResponding:
                return "История чата изменилась во время генерации. Повторите запрос."
            @unknown default:
                return "Сессия Foundation Models завершилась неизвестной ошибкой: \(error.localizedDescription)"
            }
        }

        if let serviceError = error as? ServiceError {
            return serviceError.localizedDescription
        }

        let nsError = error as NSError
        return "\(error.localizedDescription)\n\n\(nsError.domain), код \(nsError.code)"
    }

    private func persist() {
        store.save(
            PersistedAppState(
                conversations: conversations,
                selectedConversationID: selectedConversationID,
                selectedModel: modelType,
                settings: settings
            )
        )
    }
}
