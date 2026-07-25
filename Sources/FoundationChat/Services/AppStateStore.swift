import Foundation

struct PersistedAppState: Codable {
    var conversations: [Conversation]
    var selectedConversationID: UUID?
    var selectedModel: ModelType
    var settings: GenerationSettings
}

struct AppStateStore {
    private let defaults: UserDefaults
    private let storageKey = "FoundationChat.AppState.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedAppState? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(PersistedAppState.self, from: data)
    }

    func save(_ state: PersistedAppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
