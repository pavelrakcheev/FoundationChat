import AppIntents
import Foundation
import Observation

@MainActor
@Observable
final class AppIntentRouter {
    struct Request: Equatable {
        enum Action: Equatable {
            case newChat(prompt: String?, model: ModelType)
            case openChat(UUID)
        }

        let id = UUID()
        let action: Action
    }

    static let shared = AppIntentRouter()
    var request: Request?
    private init() {}
}

enum AppleModelIntentValue: String, AppEnum {
    case local
    case cloud

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Apple AI Model"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .local: "Local",
        .cloud: "Cloud"
    ]

    var modelType: ModelType { self == .local ? .local : .cloud }
}

struct ConversationEntity: AppEntity, Identifiable {
    let id: String
    let title: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Foundation Chat"
    static let defaultQuery = ConversationEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "Foundation Chat")
    }
}

struct ConversationEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ConversationEntity] {
        await MainActor.run {
            let conversations = AppStateStore().load()?.conversations ?? []
            return conversations
                .filter { identifiers.contains($0.id.uuidString) }
                .map { ConversationEntity(id: $0.id.uuidString, title: $0.title) }
        }
    }

    func suggestedEntities() async throws -> [ConversationEntity] {
        await MainActor.run {
            (AppStateStore().load()?.conversations ?? [])
                .prefix(12)
                .map { ConversationEntity(id: $0.id.uuidString, title: $0.title) }
        }
    }
}

struct NewFoundationChatIntent: AppIntent {
    static let title: LocalizedStringResource = "Новый Foundation Chat"
    static let description = IntentDescription("Открыть новый чат с Apple Foundation Model")
    static let openAppWhenRun = true

    @Parameter(title: "Запрос")
    var prompt: String?

    @Parameter(title: "Модель", default: .local)
    var model: AppleModelIntentValue

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppIntentRouter.shared.request = .init(
                action: .newChat(prompt: prompt, model: model.modelType)
            )
        }
        return .result()
    }
}

struct OpenConversationIntent: AppIntent {
    static let title: LocalizedStringResource = "Открыть Foundation Chat"
    static let openAppWhenRun = true

    @Parameter(title: "Чат")
    var conversation: ConversationEntity

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: conversation.id) {
            await MainActor.run {
                AppIntentRouter.shared.request = .init(action: .openChat(id))
            }
        }
        return .result()
    }
}

struct FoundationChatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewFoundationChatIntent(),
            phrases: [
                "Новый чат в \(.applicationName)",
                "Спросить Apple AI в \(.applicationName)"
            ],
            shortTitle: "Новый Apple AI чат",
            systemImageName: "apple.intelligence"
        )
        AppShortcut(
            intent: OpenConversationIntent(),
            phrases: ["Открыть чат в \(.applicationName)"],
            shortTitle: "Открыть чат",
            systemImageName: "bubble.left.and.bubble.right"
        )
    }
}
