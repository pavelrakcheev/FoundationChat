import Foundation
import FoundationModels
import CoreSpotlight
import Security
import Vision

struct ModelService {
    static let pccEntitlement = "com.apple.developer.private-cloud-compute"

    func readiness(for type: ModelType) async -> ModelReadiness {
        switch type {
        case .systemOnDevice:
            let model = SystemLanguageModel.default
            let limit = model.contextSize
            let capabilities = model.capabilities
            let featureValues = (
                capabilities.contains(.vision),
                capabilities.contains(.guidedGeneration),
                capabilities.contains(.reasoning)
            )

            switch model.availability {
            case .available:
                return ModelReadiness(
                    state: .ready,
                    detail: model.supportsLocale()
                        ? Self.localPrivacyDetail
                        : "Готова · текущий язык официально не поддерживается",
                    contextLimit: limit,
                    supportsVision: featureValues.0,
                    supportsGuidedGeneration: featureValues.1,
                    supportsReasoning: featureValues.2
                )
            case .unavailable(.deviceNotEligible):
                return unavailable(
                    type, detail: Self.ineligibleDeviceDetail,
                    contextLimit: limit, capabilities: featureValues
                )
            case .unavailable(.appleIntelligenceNotEnabled):
                return setup(
                    type, detail: Self.enableAppleIntelligenceDetail,
                    contextLimit: limit, capabilities: featureValues
                )
            case .unavailable(.modelNotReady):
                return setup(
                    type, detail: "Системная модель ещё загружается или готовится.",
                    contextLimit: limit, capabilities: featureValues
                )
            case .unavailable:
                return unavailable(
                    type, detail: "Системная модель недоступна.",
                    contextLimit: limit, capabilities: featureValues
                )
            @unknown default:
                return unavailable(
                    type, detail: "Статус системной модели не распознан.",
                    contextLimit: limit, capabilities: featureValues
                )
            }

        case .privateCloudCompute:
            let model = PrivateCloudComputeLanguageModel()
            let limit = (try? await model.contextSize) ?? type.fallbackContextLimit
            let capabilities = model.capabilities
            let featureValues = (
                capabilities.contains(.vision),
                capabilities.contains(.guidedGeneration),
                capabilities.contains(.reasoning)
            )

            guard Self.hasPCCEntitlement else {
                return setup(
                    type,
                    detail: "Нужны managed entitlement и подписанная тестовая сборка.",
                    contextLimit: limit,
                    capabilities: featureValues
                )
            }

            switch model.availability {
            case .available:
                if model.quotaUsage.isLimitReached {
                    return unavailable(
                        type, detail: "Дневной лимит PCC исчерпан.",
                        contextLimit: limit, capabilities: featureValues
                    )
                }
                return ModelReadiness(
                    state: .ready,
                    detail: model.supportsLocale()
                        ? "Готова · Private Cloud Compute"
                        : "Готова · текущий язык официально не поддерживается",
                    contextLimit: limit,
                    supportsVision: featureValues.0,
                    supportsGuidedGeneration: featureValues.1,
                    supportsReasoning: featureValues.2
                )
            case .unavailable(.deviceNotEligible):
                return unavailable(
                    type, detail: "Устройство или регион не поддерживает PCC.",
                    contextLimit: limit, capabilities: featureValues
                )
            case .unavailable(.systemNotReady):
                return setup(
                    type, detail: "PCC не готов: проверьте сеть и Apple Intelligence.",
                    contextLimit: limit, capabilities: featureValues
                )
            case .unavailable:
                return unavailable(
                    type, detail: "Private Cloud Compute недоступен.",
                    contextLimit: limit, capabilities: featureValues
                )
            @unknown default:
                return unavailable(
                    type, detail: "Статус Private Cloud Compute не распознан.",
                    contextLimit: limit, capabilities: featureValues
                )
            }
        }
    }

    func makeSession(
        type: ModelType,
        settings: GenerationSettings,
        history: [Message]
    ) async throws -> LanguageModelSession {
        let transcript = makeTranscript(
            instructions: settings.systemInstructions,
            history: history
        )
        var tools: [any Tool] = []
#if os(macOS)
        if settings.enableOCR { tools.append(OCRTool()) }
        if settings.enableBarcodeReader { tools.append(BarcodeReaderTool()) }
        if settings.enableSpotlightRAG { tools.append(SpotlightSearchTool()) }
#endif

        switch type {
        case .systemOnDevice:
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw ServiceError.modelNotAvailable("Apple Intelligence не готова.")
            }
            return LanguageModelSession(model: model, tools: tools, transcript: transcript)

        case .privateCloudCompute:
            guard Self.hasPCCEntitlement else {
                throw ServiceError.pccEntitlementMissing
            }
            let model = PrivateCloudComputeLanguageModel()
            guard case .available = model.availability else {
                throw ServiceError.modelNotAvailable("Private Cloud Compute не готов.")
            }
            return LanguageModelSession(model: model, tools: tools, transcript: transcript)
        }
    }

    func makePrompt(
        text: String,
        attachments: [ChatAttachment],
        supportsVision: Bool
    ) throws -> Prompt {
        if attachments.contains(where: { $0.kind == .image }) && !supportsVision {
            throw ServiceError.visionUnavailable
        }

        return Prompt {
            text
            for attachment in attachments {
                switch attachment.kind {
                case .image:
                    Attachment(imageURL: attachment.url).label(attachment.name)
                case .text:
                    if let content = attachment.extractedText {
                        "\n\nВложение «\(attachment.name)»:\n\(content)"
                    }
                case .file:
                    "\n\nПользователь прикрепил файл «\(attachment.name)». Его содержимое не было извлечено."
                }
            }
        }
    }

    private func makeTranscript(instructions: String, history: [Message]) -> Transcript {
        var entries: [Transcript.Entry] = [
            .instructions(
                Transcript.Instructions(
                    segments: [.text(.init(content: instructions))],
                    toolDefinitions: []
                )
            )
        ]

        for message in history where !message.content.isEmpty {
            let segment = Transcript.Segment.text(.init(content: message.content))
            switch message.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(segments: [segment])))
            case .assistant:
                entries.append(.response(Transcript.Response(segments: [segment])))
            case .error:
                continue
            }
        }
        return Transcript(entries: entries)
    }

    private func unavailable(
        _ type: ModelType,
        detail: String,
        contextLimit: Int,
        capabilities: (Bool, Bool, Bool)
    ) -> ModelReadiness {
        ModelReadiness(
            state: .unavailable,
            detail: detail,
            contextLimit: contextLimit,
            supportsVision: capabilities.0,
            supportsGuidedGeneration: capabilities.1,
            supportsReasoning: capabilities.2
        )
    }

    private func setup(
        _ type: ModelType,
        detail: String,
        contextLimit: Int,
        capabilities: (Bool, Bool, Bool)
    ) -> ModelReadiness {
        ModelReadiness(
            state: .requiresSetup,
            detail: detail,
            contextLimit: contextLimit,
            supportsVision: capabilities.0,
            supportsGuidedGeneration: capabilities.1,
            supportsReasoning: capabilities.2
        )
    }

    static var hasPCCEntitlement: Bool {
#if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                pccEntitlement as CFString,
                nil
              )
        else {
            return false
        }
        return (value as? Bool) == true
#else
        false
#endif
    }

    private static var localPrivacyDetail: String {
#if os(iOS)
        "Готова · данные остаются на iPhone"
#else
        "Готова · данные остаются на Mac"
#endif
    }

    private static var ineligibleDeviceDetail: String {
#if os(iOS)
        "Этот iPhone или iPad не поддерживает Apple Intelligence."
#else
        "Этот Mac не поддерживает Apple Intelligence."
#endif
    }

    private static var enableAppleIntelligenceDetail: String {
#if os(iOS)
        "Включите Apple Intelligence в Настройках iPhone."
#else
        "Включите Apple Intelligence в Системных настройках."
#endif
    }
}
