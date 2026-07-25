import Foundation
import Testing
@testable import FoundationChat

struct ChatModelsTests {
    @Test
    func appStateStorePersistsIntoAnIsolatedDefaultsSuite() throws {
        let suiteName = "FoundationChatTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conversation = Conversation(
            title: "Сохранённый чат",
            messages: [Message(role: .user, content: "Проверка")],
            modelType: .privateCloudCompute
        )
        let state = PersistedAppState(
            conversations: [conversation],
            selectedConversationID: conversation.id,
            selectedModel: .privateCloudCompute,
            settings: GenerationSettings()
        )
        let store = AppStateStore(defaults: defaults)

        store.save(state)
        let loaded = try #require(store.load())

        #expect(loaded.conversations == [conversation])
        #expect(loaded.selectedConversationID == conversation.id)
        #expect(loaded.selectedModel == .privateCloudCompute)
    }

    @Test
    func persistedStateRoundTrips() throws {
        let conversation = Conversation(
            title: "Проверка",
            messages: [
                Message(role: .user, content: "Привет"),
                Message(role: .assistant, content: "**Привет!**")
            ],
            modelType: .systemOnDevice
        )
        let state = PersistedAppState(
            conversations: [conversation],
            selectedConversationID: conversation.id,
            selectedModel: .systemOnDevice,
            settings: GenerationSettings()
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedAppState.self, from: data)

        #expect(decoded.conversations == state.conversations)
        #expect(decoded.selectedConversationID == conversation.id)
        #expect(decoded.settings.systemInstructions == GenerationSettings.defaultInstructions)
    }

    @Test
    func onlyReasoningModelsExposeReasoningControl() {
        #expect(!ModelType.systemOnDevice.supportsReasoning)
        #expect(ModelType.privateCloudCompute.supportsReasoning)
    }

    @Test
    func legacyConversationDecodesWithFolderAndPinDefaults() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 100)
        let legacy: [String: Any] = [
            "id": id.uuidString,
            "title": "Legacy",
            "messages": [],
            "createdAt": date.timeIntervalSinceReferenceDate,
            "updatedAt": date.timeIntervalSinceReferenceDate,
            "modelType": ModelType.systemOnDevice.rawValue
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        #expect(decoded.folderID == nil)
        #expect(!decoded.isPinned)
    }

    @Test
    func generationMetricsCalculateVisibleTokenSpeed() {
        let metrics = GenerationMetrics(
            outputTokens: 120,
            reasoningTokens: 20,
            duration: 2,
            reasoning: "Проверка"
        )
        #expect(metrics.tokensPerSecond == 50)
    }

    @Test
    func bundledPromptLibraryContainsAppleOnlyResearchPresets() {
        let state = PersistedAppState(
            conversations: [],
            selectedConversationID: nil,
            selectedModel: .local,
            settings: GenerationSettings()
        )
        #expect(state.promptPresets.contains(where: { $0.id == PromptPreset.standard.id }))
        #expect(state.promptPresets.contains(where: { $0.id == PromptPreset.siriCommunity.id }))
        #expect(ModelType.allCases.count == 2)
    }
}
