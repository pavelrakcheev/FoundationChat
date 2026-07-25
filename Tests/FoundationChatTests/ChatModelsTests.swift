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
}
