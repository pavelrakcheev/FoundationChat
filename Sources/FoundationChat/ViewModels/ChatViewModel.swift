import Foundation
import FoundationModels
import SwiftUI

@Generable
private struct GuidedChatResponse {
    @Guide(description: "Полный ответ пользователю в Markdown")
    var answer: String
    @Guide(description: "Короткие ключевые тезисы")
    var keyPoints: [String]
}

@MainActor
@Observable
final class ChatViewModel {
    var conversations: [Conversation]
    var folders: [ChatFolder]
    var promptPresets: [PromptPreset]
    var pendingAttachments: [ChatAttachment] = []
    private(set) var toolEvents: [ToolEvent] = []
    private(set) var evaluationResults: [EvaluationResult] = []
    private(set) var isEvaluating = false
    private(set) var exportedFileURL: URL?
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
            if oldValue != settings {
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
        let settings: GenerationSettings
    }

    private var sessions: [UUID: SessionRecord] = [:]
    private var usageByConversation: [UUID: ContextInfo] = [:]
    private var currentTask: Task<Void, Never>?
    private var generationConversationID: UUID?
    private let service = ModelService()
    private let attachmentStore = AttachmentStore()
    private let store: AppStateStore

    init(store: AppStateStore = AppStateStore()) {
        self.store = store
        if let saved = store.load() {
            conversations = saved.conversations
            selectedConversationID = saved.selectedConversationID
            modelType = saved.selectedModel
            settings = saved.settings
            folders = saved.folders
            promptPresets = saved.promptPresets
        } else {
            conversations = []
            selectedConversationID = nil
            modelType = .local
            settings = GenerationSettings()
            folders = []
            promptPresets = [.standard, .siriCommunity]
        }
        readiness = Dictionary(
            uniqueKeysWithValues: ModelType.allCases.map { ($0, .checking(for: $0)) }
        )
        sortConversations()
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
            let id = conversations[index].id
            conversations[index].modelType = type
            conversations[index].updatedAt = Date()
            sessions.removeValue(forKey: id)
            usageByConversation.removeValue(forKey: id)
            sortConversations()
        }
        updateContextInfo()
        persist()
        Task { await refreshAvailability(for: type) }
    }

    func sendMessage(_ text: String, attachments: [ChatAttachment] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, !isProcessing else { return }
        guard currentReadiness.canGenerate else {
            errorMessage = currentReadiness.detail
            return
        }

        let conversationID = ensureConversation()
        let type = modelType
        let settingsSnapshot = settings
        let readinessSnapshot = currentReadiness
        let existingHistory = messages(in: conversationID)

        currentTask = Task { [weak self] in
            guard let self else { return }
            isProcessing = true
            generationConversationID = conversationID
            errorMessage = nil
            let assistantID = UUID()
            let startedAt = Date()
            var producedContent = false
            var latestReasoning: String?

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
                let prompt = try service.makePrompt(
                    text: trimmed,
                    attachments: attachments,
                    supportsVision: readinessSnapshot.supportsVision
                )
                appendMessage(
                    Message(role: .user, content: trimmed, attachments: attachments),
                    to: conversationID
                )
                appendMessage(
                    Message(id: assistantID, role: .assistant, content: ""),
                    to: conversationID
                )
                updateConversationTitleIfNeeded(conversationID: conversationID, userText: trimmed)
                sortConversations()
                persist()

                let options = GenerationOptions(
                    temperature: settingsSnapshot.temperature,
                    maximumResponseTokens: settingsSnapshot.useMaxTokens
                        ? settingsSnapshot.maxTokens : nil
                )
                let contextOptions = ContextOptions(
                    reasoningLevel: reasoningLevel(for: type, setting: settingsSnapshot.reasoningLevel)
                )
                if settingsSnapshot.guidedGeneration {
                    let stream = session.streamResponse(
                        to: prompt,
                        generating: GuidedChatResponse.self,
                        options: options,
                        contextOptions: contextOptions
                    )
                    for try await snapshot in stream {
                        guard !Task.isCancelled else { break }
                        let content = snapshot.rawContent.jsonString
                        producedContent = !content.isEmpty
                        latestReasoning = reasoningText(in: snapshot.transcriptEntries)
                            ?? latestReasoning
                        updateMessage(
                            assistantID,
                            in: conversationID,
                            content: "```json\n\(content)\n```"
                        )
                        applyUsage(snapshot.usage, modelType: type, conversationID: conversationID)
                        updateMetrics(
                            assistantID,
                            in: conversationID,
                            startedAt: startedAt,
                            outputTokens: snapshot.usage.output.totalTokenCount,
                            reasoningTokens: snapshot.usage.output.reasoningTokenCount,
                            reasoning: latestReasoning
                        )
                        recordToolEvents(in: snapshot.transcriptEntries)
                    }
                } else {
                    let stream = session.streamResponse(
                        to: prompt,
                        options: options,
                        contextOptions: contextOptions
                    )
                    for try await snapshot in stream {
                        guard !Task.isCancelled else { break }
                        producedContent = !snapshot.content.isEmpty
                        latestReasoning = reasoningText(in: snapshot.transcriptEntries)
                            ?? latestReasoning
                        updateMessage(assistantID, in: conversationID, content: snapshot.content)
                        applyUsage(snapshot.usage, modelType: type, conversationID: conversationID)
                        updateMetrics(
                            assistantID,
                            in: conversationID,
                            startedAt: startedAt,
                            outputTokens: snapshot.usage.output.totalTokenCount,
                            reasoningTokens: snapshot.usage.output.reasoningTokenCount,
                            reasoning: latestReasoning
                        )
                        recordToolEvents(in: snapshot.transcriptEntries)
                    }
                }

                if Task.isCancelled {
                    resetSession(for: conversationID)
                    if producedContent {
                        appendInterruptionNote(to: assistantID, in: conversationID)
                    } else {
                        removeMessage(assistantID, from: conversationID)
                    }
                }
            } catch {
                resetSession(for: conversationID)
                if !Task.isCancelled {
                    if !hasMessage(assistantID, in: conversationID) {
                        appendMessage(
                            Message(role: .user, content: trimmed, attachments: attachments),
                            to: conversationID
                        )
                        updateConversationTitleIfNeeded(
                            conversationID: conversationID,
                            userText: trimmed
                        )
                    } else {
                        removeMessage(assistantID, from: conversationID)
                    }
                    appendMessage(Message(role: .error, content: describe(error)), to: conversationID)
                    sortConversations()
                    await refreshAvailability(for: type)
                }
            }
        }
    }

    func cancelGeneration() { currentTask?.cancel() }

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
        if generationConversationID == id { cancelGeneration() }
        resetSession(for: id)
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
        if generationConversationID == id { cancelGeneration() }
        conversations[index].messages.removeAll()
        conversations[index].title = "Новый чат"
        conversations[index].updatedAt = Date()
        resetSession(for: id)
        updateContextInfo()
        persist()
    }

    func renameConversation(_ id: UUID, to name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = String(value.prefix(80))
        conversations[index].updatedAt = Date()
        persist()
    }

    func togglePinned(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isPinned.toggle()
        conversations[index].updatedAt = Date()
        sortConversations()
        persist()
    }

    @discardableResult
    func createFolder(named name: String) -> UUID? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let folder = ChatFolder(name: String(value.prefix(60)))
        folders.append(folder)
        persist()
        return folder.id
    }

    func renameFolder(_ id: UUID, to name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }
        folders[index].name = String(value.prefix(60))
        persist()
    }

    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for index in conversations.indices where conversations[index].folderID == id {
            conversations[index].folderID = nil
        }
        persist()
    }

    func moveConversation(_ conversationID: UUID, to folderID: UUID?) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        conversations[index].folderID = folderID
        persist()
    }

    func addPrompt(name: String, instructions: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !instructions.isEmpty else { return }
        promptPresets.append(
            PromptPreset(name: String(name.prefix(60)), instructions: instructions)
        )
        persist()
    }

    func updatePrompt(_ id: UUID, name: String, instructions: String) {
        guard let index = promptPresets.firstIndex(where: { $0.id == id }),
              !promptPresets[index].isBuiltIn else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !instructions.isEmpty else { return }
        promptPresets[index].name = String(name.prefix(60))
        promptPresets[index].instructions = instructions
        persist()
    }

    func deletePrompt(_ id: UUID) {
        promptPresets.removeAll { $0.id == id && !$0.isBuiltIn }
        persist()
    }

    func applyPrompt(_ preset: PromptPreset) {
        settings.systemInstructions = preset.instructions
    }

    func importAttachments(_ urls: [URL]) {
        for url in urls {
            do {
                pendingAttachments.append(try attachmentStore.importFile(url))
            } catch {
                errorMessage = "Не удалось прикрепить «\(url.lastPathComponent)»."
            }
        }
    }

    func removePendingAttachment(_ id: UUID) {
        guard let attachment = pendingAttachments.first(where: { $0.id == id }) else { return }
        attachmentStore.remove(attachment)
        pendingAttachments.removeAll { $0.id == id }
    }

    func consumePendingAttachments() -> [ChatAttachment] {
        defer { pendingAttachments.removeAll() }
        return pendingAttachments
    }

    func exportFeedback(for message: Message, positive: Bool) {
        guard let conversationID = selectedConversationID,
              let session = sessions[conversationID]?.session else {
            errorMessage = "Feedback attachment доступен после ответа активной сессии."
            return
        }
        let data = session.logFeedbackAttachment(
            sentiment: positive ? .positive : .negative,
            desiredResponseText: positive ? nil : message.content
        )
#if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FoundationChat-feedback-\(message.id.uuidString).attachment"
        panel.prompt = "Экспортировать"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "Не удалось сохранить feedback attachment: \(error.localizedDescription)"
        }
#else
        export(
            data,
            named: "FoundationChat-feedback-\(message.id.uuidString).attachment"
        )
#endif
    }

    func runEvaluationSuite() async {
        guard currentReadiness.canGenerate, !isEvaluating, !isProcessing else { return }
        isEvaluating = true
        evaluationResults = []
        defer { isEvaluating = false }

        let cases = [
            (
                "Следование инструкции",
                "Ответь одним словом: FOUNDATION",
                { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare("FOUNDATION") == .orderedSame }
            ),
            (
                "Markdown",
                "Верни маркированный список из двух названий моделей Apple: Local и Cloud.",
                { (value: String) in
                    let hasListMarker = ["- ", "* ", "• ", "1. "].contains {
                        value.contains($0)
                    }
                    return hasListMarker && value.contains("Local") && value.contains("Cloud")
                }
            )
        ]

        for item in cases {
            let started = Date()
            do {
                let session = try await service.makeSession(
                    type: modelType,
                    settings: settings,
                    history: []
                )
                let response = try await session.respond(
                    to: item.1,
                    options: GenerationOptions(
                        temperature: 0,
                        maximumResponseTokens: 256
                    )
                )
                let passed = item.2(response.content)
                evaluationResults.append(
                    EvaluationResult(
                        name: item.0,
                        passed: passed,
                        detail: String(response.content.prefix(160)),
                        duration: Date().timeIntervalSince(started)
                    )
                )
            } catch {
                evaluationResults.append(
                    EvaluationResult(
                        name: item.0,
                        passed: false,
                        detail: describe(error),
                        duration: Date().timeIntervalSince(started)
                    )
                )
            }
        }
    }

    func exportDiagnostics() {
        let payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "model": modelType.fullName,
            "readiness": currentReadiness.detail,
            "contextLimit": contextInfo.contextLimit,
            "inputTokens": contextInfo.inputTokens,
            "outputTokens": contextInfo.outputTokens,
            "reasoningTokens": contextInfo.reasoningTokens,
            "toolCalls": toolEvents.map {
                ["name": $0.name, "createdAt": ISO8601DateFormatter().string(from: $0.createdAt)]
            },
            "privacy": "Prompts, responses, file paths and attachment contents are intentionally omitted."
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
#if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "FoundationChat-diagnostics.json"
            panel.prompt = "Экспортировать"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
#else
            export(data, named: "FoundationChat-diagnostics.json")
#endif
        } catch {
            errorMessage = "Не удалось экспортировать диагностику: \(error.localizedDescription)"
        }
    }

    func openFoundationModelsInstruments() {
#if os(macOS)
        let candidates = [
            "/Applications/Xcode-beta.app/Contents/Applications/Instruments.app",
            "/Applications/Xcode.app/Contents/Applications/Instruments.app"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        else {
            errorMessage = "Instruments не найден. Установите Xcode."
            return
        }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: NSWorkspace.OpenConfiguration()
        )
#else
        errorMessage = "Foundation Models Instruments запускается из Xcode на Mac."
#endif
    }

    func resetInstructions() { settings.systemInstructions = GenerationSettings.defaultInstructions }
    func dismissError() { errorMessage = nil }

    private var selectedConversationIndex: Int? {
        guard let id = selectedConversationID else { return nil }
        return conversations.firstIndex { $0.id == id }
    }

    private func ensureConversation() -> UUID {
        selectedConversationID ?? createNewConversation()
    }

    private func session(
        for conversationID: UUID,
        type: ModelType,
        settings: GenerationSettings,
        history: [Message]
    ) async throws -> LanguageModelSession {
        if let record = sessions[conversationID],
           record.modelType == type,
           record.settings == settings {
            return record.session
        }
        let session = try await service.makeSession(type: type, settings: settings, history: history)
        sessions[conversationID] = SessionRecord(
            session: session,
            modelType: type,
            settings: settings
        )
        return session
    }

    private func reasoningLevel(
        for type: ModelType,
        setting: GenerationSettings.ReasoningLevel
    ) -> ContextOptions.ReasoningLevel? {
        guard type.supportsReasoning else { return nil }
        switch setting {
        case .none: return nil
        case .light: return .light
        case .moderate: return .moderate
        case .deep: return .deep
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

    private func updateMessage(_ messageID: UUID, in conversationID: UUID, content: String) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
                  $0.id == messageID
              }) else { return }
        conversations[conversationIndex].messages[messageIndex].content = content
        conversations[conversationIndex].updatedAt = Date()
    }

    private func updateMetrics(
        _ messageID: UUID,
        in conversationID: UUID,
        startedAt: Date,
        outputTokens: Int,
        reasoningTokens: Int,
        reasoning: String?
    ) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
                  $0.id == messageID
              }) else { return }
        conversations[conversationIndex].messages[messageIndex].metrics = GenerationMetrics(
            outputTokens: outputTokens,
            reasoningTokens: reasoningTokens,
            duration: max(Date().timeIntervalSince(startedAt), 0.001),
            reasoning: reasoning
        )
    }

    private func reasoningText(in entries: ArraySlice<Transcript.Entry>) -> String? {
        let value = entries.compactMap { entry -> String? in
            guard case .reasoning(let reasoning) = entry else { return nil }
            return reasoning.segments.compactMap { segment -> String? in
                guard case .text(let text) = segment else { return nil }
                return text.content
            }.joined(separator: "\n")
        }.joined(separator: "\n")
        return value.isEmpty ? nil : value
    }

    private func recordToolEvents(in entries: ArraySlice<Transcript.Entry>) {
        for entry in entries {
            guard case .toolCalls(let calls) = entry else { continue }
            for call in calls where !toolEvents.contains(where: { $0.id == call.id }) {
                toolEvents.insert(
                    ToolEvent(
                        id: call.id,
                        name: call.toolName,
                        argumentsJSON: call.arguments.jsonString
                    ),
                    at: 0
                )
            }
        }
        if toolEvents.count > 50 {
            toolEvents.removeLast(toolEvents.count - 50)
        }
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
              }) else { return }
        conversations[conversationIndex].messages[messageIndex].content +=
            "\n\n*Генерация остановлена пользователем.*"
    }

    private func updateConversationTitleIfNeeded(conversationID: UUID, userText: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              conversations[index].title == "Новый чат" else { return }
        let firstLine = userText.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        conversations[index].title = firstLine.isEmpty ? "Вложения" : String(firstLine.prefix(52))
    }

    private func syncModelWithSelectedConversation() {
        guard let conversation = selectedConversation else { return }
        modelType = conversation.modelType
    }

    private func sortConversations() {
        conversations.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func resetSession(for id: UUID) {
        sessions.removeValue(forKey: id)
        usageByConversation.removeValue(forKey: id)
    }

    private func applyUsage(
        _ usage: LanguageModelSession.Usage,
        modelType: ModelType,
        conversationID: UUID
    ) {
        let info = ContextInfo(
            modelName: modelType.fullName,
            contextLimit: readiness[modelType]?.contextLimit ?? modelType.fallbackContextLimit,
            inputTokens: usage.input.totalTokenCount,
            outputTokens: usage.output.totalTokenCount,
            cachedTokens: usage.input.cachedTokenCount,
            reasoningTokens: usage.output.reasoningTokenCount,
            isExact: true
        )
        usageByConversation[conversationID] = info
        if selectedConversationID == conversationID { contextInfo = info }
    }

    private func updateContextInfo() {
        let limit = readiness[modelType]?.contextLimit ?? modelType.fallbackContextLimit
        let text = selectedConversation?.messages
            .filter { $0.role != .error }
            .map(\.content).joined(separator: "\n") ?? ""
        let estimated = max(0, (text.count + settings.systemInstructions.count) / 4)
        if let id = selectedConversationID,
           sessions[id] != nil,
           var exact = usageByConversation[id] {
            exact.contextLimit = limit
            contextInfo = exact
        } else {
            contextInfo = ContextInfo(
                modelName: modelType.fullName,
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
                return detail.resetDate.map {
                    "Лимит Private Cloud Compute исчерпан. Сброс: \($0.formatted())."
                } ?? "Лимит Private Cloud Compute исчерпан."
            case .serviceUnavailable(let detail):
                return "Private Cloud Compute временно недоступен.\n\n\(detail.debugDescription)"
            @unknown default:
                return "Private Cloud Compute вернул неизвестную ошибку."
            }
        }
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded(let detail):
                return "Контекст переполнен: \(detail.tokenCount) из \(detail.contextSize) токенов."
            case .rateLimited(let detail):
                return detail.resetDate.map {
                    "Слишком много запросов. Повторите после \($0.formatted())."
                } ?? "Слишком много запросов. Повторите позже."
            case .guardrailViolation: return "Ответ остановлен ограничениями безопасности."
            case .refusal: return "Модель отказалась выполнить запрос."
            case .unsupportedCapability: return "Apple-модель не поддерживает эту возможность."
            case .unsupportedTranscriptContent: return "История содержит неподдерживаемый элемент."
            case .unsupportedGenerationGuide: return "Модель не поддерживает выбранную схему."
            case .unsupportedLanguageOrLocale: return "Модель не поддерживает язык запроса."
            case .timeout: return "Модель не успела ответить. Повторите запрос."
            @unknown default: return "Foundation Models вернул неизвестную ошибку."
            }
        }
        if let error = error as? LanguageModelSession.Error {
            switch error {
            case .concurrentRequests: return "Сессия уже обрабатывает другой запрос."
            case .transcriptMutationWhileResponding: return "История изменилась во время генерации."
            @unknown default: return "Сессия завершилась неизвестной ошибкой."
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
                settings: settings,
                folders: folders,
                promptPresets: promptPresets
            )
        )
        let spotlightItems = conversations.map {
            SpotlightIndexer.Item(
                id: $0.id.uuidString,
                title: $0.title,
                model: $0.modelType.shortName
            )
        }
        Task { await SpotlightIndexer.shared.index(spotlightItems) }
    }

#if os(iOS)
    private func export(_ data: Data, named name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            exportedFileURL = url
        } catch {
            errorMessage = "Не удалось подготовить файл: \(error.localizedDescription)"
        }
    }
#endif
}
