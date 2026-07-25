import Foundation
import AppKit
import PDFKit

struct PersistedAppState: Codable {
    var conversations: [Conversation]
    var selectedConversationID: UUID?
    var selectedModel: ModelType
    var settings: GenerationSettings
    var folders: [ChatFolder]
    var promptPresets: [PromptPreset]

    init(
        conversations: [Conversation],
        selectedConversationID: UUID?,
        selectedModel: ModelType,
        settings: GenerationSettings,
        folders: [ChatFolder] = [],
        promptPresets: [PromptPreset] = [.standard, .siriCommunity]
    ) {
        self.conversations = conversations
        self.selectedConversationID = selectedConversationID
        self.selectedModel = selectedModel
        self.settings = settings
        self.folders = folders
        self.promptPresets = promptPresets
    }

    private enum CodingKeys: String, CodingKey {
        case conversations, selectedConversationID, selectedModel, settings, folders, promptPresets
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        conversations = try values.decodeIfPresent([Conversation].self, forKey: .conversations) ?? []
        selectedConversationID = try values.decodeIfPresent(UUID.self, forKey: .selectedConversationID)
        selectedModel = try values.decodeIfPresent(ModelType.self, forKey: .selectedModel) ?? .local
        settings = try values.decodeIfPresent(GenerationSettings.self, forKey: .settings)
            ?? GenerationSettings()
        folders = try values.decodeIfPresent([ChatFolder].self, forKey: .folders) ?? []
        promptPresets = try values.decodeIfPresent([PromptPreset].self, forKey: .promptPresets)
            ?? [.standard, .siriCommunity]
        if !promptPresets.contains(where: { $0.id == PromptPreset.standard.id }) {
            promptPresets.insert(.standard, at: 0)
        }
        if !promptPresets.contains(where: { $0.id == PromptPreset.siriCommunity.id }) {
            promptPresets.insert(.siriCommunity, at: min(1, promptPresets.count))
        }
    }
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

struct AttachmentStore {
    private let fileManager = FileManager.default

    func importFile(_ source: URL) throws -> ChatAttachment {
        let directory = try attachmentDirectory()
        let target = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension)
        try fileManager.copyItem(at: source, to: target)

        let imageExtensions = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "webp"]
        let textExtensions = [
            "txt", "md", "json", "csv", "xml", "swift", "py", "js", "ts",
            "html", "yaml", "yml"
        ]
        let ext = source.pathExtension.lowercased()
        let extractedText: String?
        if ext == "pdf" {
            extractedText = PDFDocument(url: target)?.string
        } else if ext == "rtf" || ext == "rtfd" {
            extractedText = try? NSAttributedString(
                url: target,
                options: [:],
                documentAttributes: nil
            ).string
        } else if textExtensions.contains(ext) {
            extractedText = try? String(contentsOf: target, encoding: .utf8)
        } else {
            extractedText = nil
        }
        let kind: ChatAttachment.Kind = imageExtensions.contains(ext)
            ? .image
            : (extractedText == nil ? .file : .text)

        return ChatAttachment(
            name: source.lastPathComponent,
            localPath: target.path,
            kind: kind,
            extractedText: extractedText
        )
    }

    func remove(_ attachment: ChatAttachment) {
        try? fileManager.removeItem(at: attachment.url)
    }

    private func attachmentDirectory() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support
            .appendingPathComponent("FoundationChat", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
