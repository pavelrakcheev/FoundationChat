import Foundation
import FoundationModels
import Security

struct ModelService {
    static let pccEntitlement = "com.apple.developer.private-cloud-compute"

    func readiness(for type: ModelType) async -> ModelReadiness {
        switch type {
        case .systemOnDevice:
            let model = SystemLanguageModel.default
            let limit = model.contextSize

            switch model.availability {
            case .available:
                if !model.supportsLocale() {
                    return ModelReadiness(
                        state: .ready,
                        detail: "Готова · текущий язык официально не поддерживается",
                        contextLimit: limit
                    )
                }
                return ModelReadiness(
                    state: .ready,
                    detail: "Готова · полностью локально",
                    contextLimit: limit
                )
            case .unavailable(.deviceNotEligible):
                return ModelReadiness(
                    state: .unavailable,
                    detail: "Этот Mac не поддерживает Apple Intelligence.",
                    contextLimit: limit
                )
            case .unavailable(.appleIntelligenceNotEnabled):
                return ModelReadiness(
                    state: .requiresSetup,
                    detail: "Включите Apple Intelligence в Системных настройках.",
                    contextLimit: limit
                )
            case .unavailable(.modelNotReady):
                return ModelReadiness(
                    state: .requiresSetup,
                    detail: "Системная модель ещё загружается или готовится.",
                    contextLimit: limit
                )
            case .unavailable:
                return ModelReadiness(
                    state: .unavailable,
                    detail: "Системная модель недоступна по неизвестной причине.",
                    contextLimit: limit
                )
            @unknown default:
                return ModelReadiness(
                    state: .unavailable,
                    detail: "Статус системной модели не распознан.",
                    contextLimit: limit
                )
            }

        case .privateCloudCompute:
            let model = PrivateCloudComputeLanguageModel()
            let limit = (try? await model.contextSize) ?? type.fallbackContextLimit

            guard Self.hasPCCEntitlement else {
                return ModelReadiness(
                    state: .requiresSetup,
                    detail: "Нужны managed entitlement и подписанная тестовая сборка.",
                    contextLimit: limit
                )
            }

            switch model.availability {
            case .available:
                if !model.supportsLocale() {
                    return ModelReadiness(
                        state: .ready,
                        detail: "Готова · текущий язык официально не поддерживается",
                        contextLimit: limit
                    )
                }
                if model.quotaUsage.isLimitReached {
                    return ModelReadiness(
                        state: .unavailable,
                        detail: "Дневной лимит PCC исчерпан.",
                        contextLimit: limit
                    )
                }
                return ModelReadiness(
                    state: .ready,
                    detail: "Готова · защищено Private Cloud Compute",
                    contextLimit: limit
                )
            case .unavailable(.deviceNotEligible):
                return ModelReadiness(
                    state: .unavailable,
                    detail: "Устройство или регион не поддерживает PCC.",
                    contextLimit: limit
                )
            case .unavailable(.systemNotReady):
                return ModelReadiness(
                    state: .requiresSetup,
                    detail: "PCC не готов: проверьте сеть и Apple Intelligence.",
                    contextLimit: limit
                )
            case .unavailable:
                return ModelReadiness(
                    state: .unavailable,
                    detail: "Private Cloud Compute недоступен по неизвестной причине.",
                    contextLimit: limit
                )
            @unknown default:
                return ModelReadiness(
                    state: .unavailable,
                    detail: "Статус Private Cloud Compute не распознан.",
                    contextLimit: limit
                )
            }
        }
    }

    func makeSession(
        type: ModelType,
        instructions: String,
        history: [Message]
    ) async throws -> LanguageModelSession {
        let transcript = makeTranscript(instructions: instructions, history: history)

        switch type {
        case .systemOnDevice:
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw ServiceError.modelNotAvailable("Apple Intelligence не готова.")
            }
            return LanguageModelSession(model: model, transcript: transcript)

        case .privateCloudCompute:
            guard Self.hasPCCEntitlement else {
                throw ServiceError.pccEntitlementMissing
            }
            let model = PrivateCloudComputeLanguageModel()
            guard case .available = model.availability else {
                throw ServiceError.modelNotAvailable("Private Cloud Compute не готов.")
            }
            return LanguageModelSession(model: model, transcript: transcript)
        }
    }

    private func makeTranscript(
        instructions: String,
        history: [Message]
    ) -> Transcript {
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

    static var hasPCCEntitlement: Bool {
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
    }
}
