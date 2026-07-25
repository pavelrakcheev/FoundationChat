import SwiftUI

struct WelcomeView: View {
    let modelType: ModelType
    let readiness: ModelReadiness
    let chooseSuggestion: (String) -> Void

    private let suggestions = Array(WelcomeSuggestion.all.prefix(4))
    private let columns = [
        GridItem(.fixed(170), spacing: 12),
        GridItem(.fixed(170), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                modelStatus
                capabilities
                footerHint
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("Что попробуем?")
                .font(.largeTitle.weight(.semibold))

            Text(
                "Apple Foundation Models помогают работать с текстом, изображениями "
                    + "и данными прямо внутри приложения."
            )
            .font(.title3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 610)
        }
    }

    private var modelStatus: some View {
        HStack(spacing: 9) {
            Label(modelType.fullName, systemImage: modelType.iconName)
                .fontWeight(.medium)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(readiness.detail)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .font(.callout)
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    private var capabilities: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(suggestions) { suggestion in
                Button {
                    chooseSuggestion(suggestion.prompt)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: suggestion.systemImage)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(height: 24)

                        Text(suggestion.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(suggestion.explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)

                        Spacer(minLength: 0)

                        HStack {
                            Text(suggestion.badge)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 138, height: 138, alignment: .topLeading)
                    .padding(16)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                .help("Подставить пример запроса")
            }
        }
    }

    private var footerHint: some View {
        Label(
            "Можно перетащить файл в окно или прикрепить его кнопкой +",
            systemImage: "paperclip"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct WelcomeSuggestion: Identifiable {
    let id: String
    let title: String
    let explanation: String
    let badge: String
    let systemImage: String
    let prompt: String

    static let all: [WelcomeSuggestion] = [
        WelcomeSuggestion(
            id: "summarize",
            title: "Разобрать документ",
            explanation: "Получить краткое резюме, решения, сроки и список следующих шагов.",
            badge: "Текст и файлы",
            systemImage: "doc.text.magnifyingglass",
            prompt: "Кратко резюмируй документ. Отдельно выдели решения, сроки, риски и следующие шаги."
        ),
        WelcomeSuggestion(
            id: "vision",
            title: "Понять изображение",
            explanation: "Описать сцену, прочитать текст, найти штрихкод или объяснить диаграмму.",
            badge: "Vision · OCR",
            systemImage: "photo.badge.magnifyingglass",
            prompt: "Проанализируй прикреплённое изображение: опиши главное, прочитай текст и отметь важные детали."
        ),
        WelcomeSuggestion(
            id: "structure",
            title: "Структурировать данные",
            explanation: "Превратить свободный текст в пункты, таблицу или проверяемый JSON.",
            badge: "Guided generation",
            systemImage: "curlybraces.square",
            prompt: "Преобразуй данные ниже в чёткую структуру: краткое резюме, категории, факты и действия."
        ),
        WelcomeSuggestion(
            id: "rewrite",
            title: "Улучшить текст",
            explanation: "Переписать письмо, заметку или описание яснее, короче и в нужном тоне.",
            badge: "Локально",
            systemImage: "text.badge.checkmark",
            prompt: "Перепиши текст яснее и короче, сохрани смысл и предложи две версии: нейтральную и дружелюбную."
        ),
        WelcomeSuggestion(
            id: "spotlight",
            title: "Найти на Mac",
            explanation: "Использовать локальный Spotlight RAG, чтобы ответить по вашим проиндексированным данным.",
            badge: "Spotlight RAG",
            systemImage: "magnifyingglass.circle",
            prompt: "Найди через Spotlight материалы по моей теме и составь краткую сводку со списком найденного."
        ),
        WelcomeSuggestion(
            id: "plan",
            title: "Составить план",
            explanation: "Разбить идею или задачу на понятные этапы, риски и критерии готовности.",
            badge: "Tool calling",
            systemImage: "checklist",
            prompt: "Разбей мою задачу на реалистичный пошаговый план. Укажи риски, зависимости и критерии готовности."
        )
    ]
}
