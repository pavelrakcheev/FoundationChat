import Foundation

struct GenerationSettings: Codable, Hashable {
    static let defaultInstructions = """
    Ты — полезный ассистент в приложении Foundation Chat.
    Всегда отвечай на языке пользователя, если он не попросил иначе.
    Будь точным, честно отмечай неопределённость и не выдумывай факты.
    Форматируй ответы как GitHub Flavored Markdown: используй короткие абзацы, списки, \
    заголовки и fenced code blocks, когда это улучшает читаемость. Не оборачивай весь \
    ответ в один code block.
    """

    var temperature: Double = 0.7
    var maxTokens: Int = 2048
    var systemInstructions: String = Self.defaultInstructions
    var reasoningLevel: ReasoningLevel = .moderate
    var useMaxTokens = false

    enum ReasoningLevel: String, Codable, Hashable, CaseIterable, Identifiable {
        case none
        case light
        case moderate
        case deep

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .none: "Без reasoning"
            case .light: "Лёгкий"
            case .moderate: "Умеренный"
            case .deep: "Глубокий"
            }
        }
    }
}

struct ContextInfo: Hashable {
    var modelName: String
    var contextLimit: Int
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var reasoningTokens: Int
    var isExact: Bool

    var usedTokens: Int { inputTokens + outputTokens }

    var usageRatio: Double {
        guard contextLimit > 0 else { return 0 }
        return min(Double(usedTokens) / Double(contextLimit), 1)
    }

    static let empty = ContextInfo(
        modelName: ModelType.systemOnDevice.displayName,
        contextLimit: 4096,
        inputTokens: 0,
        outputTokens: 0,
        cachedTokens: 0,
        reasoningTokens: 0,
        isExact: false
    )
}

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var modelType: ModelType

    init(
        id: UUID = UUID(),
        title: String = "Новый чат",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelType: ModelType = .systemOnDevice
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelType = modelType
    }
}

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    var role: MessageRole
    var content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum MessageRole: String, Codable, Hashable {
    case user
    case assistant
    case error
}

enum ModelType: String, Codable, Hashable, CaseIterable, Identifiable {
    case systemOnDevice
    case privateCloudCompute

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemOnDevice: "Apple Intelligence · локально"
        case .privateCloudCompute: "Private Cloud Compute"
        }
    }

    var shortName: String {
        switch self {
        case .systemOnDevice: "On‑Device"
        case .privateCloudCompute: "PCC"
        }
    }

    var description: String {
        switch self {
        case .systemOnDevice:
            "Системная Apple Foundation Model. Работает офлайн и не покидает Mac."
        case .privateCloudCompute:
            "Более крупная модель Apple с контекстом 32K и reasoning. Требует managed entitlement."
        }
    }

    var iconName: String {
        switch self {
        case .systemOnDevice: "apple.intelligence"
        case .privateCloudCompute: "cloud"
        }
    }

    var supportsReasoning: Bool {
        self == .privateCloudCompute
    }

    var fallbackContextLimit: Int {
        switch self {
        case .systemOnDevice: 4096
        case .privateCloudCompute: 32_768
        }
    }
}

struct ModelReadiness: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case checking
        case ready
        case requiresSetup
        case unavailable
    }

    var state: State
    var detail: String
    var contextLimit: Int

    var canGenerate: Bool { state == .ready }

    static func checking(for model: ModelType) -> ModelReadiness {
        ModelReadiness(
            state: .checking,
            detail: "Проверяем доступность…",
            contextLimit: model.fallbackContextLimit
        )
    }
}

enum ServiceError: LocalizedError {
    case modelNotAvailable(String)
    case pccEntitlementMissing

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let detail):
            "Модель недоступна: \(detail)"
        case .pccEntitlementMissing:
            "Для Private Cloud Compute нужен managed entitlement com.apple.developer.private-cloud-compute и подписанная тестовая сборка."
        }
    }
}
