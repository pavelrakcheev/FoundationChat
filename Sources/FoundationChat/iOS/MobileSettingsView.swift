#if os(iOS)
import SwiftUI

private enum MobileSettingsSection: String, CaseIterable, Identifiable {
    case generation = "Ответ"
    case instructions = "Инструкции"
    case models = "Модель"

    var id: String { rawValue }
}

private enum MobilePromptEditorTarget: Identifiable {
    case create
    case edit(PromptPreset)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let preset): preset.id.uuidString
        }
    }

    var preset: PromptPreset? {
        if case .edit(let preset) = self { preset } else { nil }
    }
}

struct MobileSettingsView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var section: MobileSettingsSection = .generation
    @State private var promptEditorTarget: MobilePromptEditorTarget?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Раздел", selection: $section) {
                    ForEach(MobileSettingsSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch section {
                case .generation:
                    generationForm
                case .instructions:
                    instructionsForm
                case .models:
                    modelsForm
                }
            }
            .navigationTitle("Параметры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .sheet(item: $promptEditorTarget) { target in
            MobilePromptEditorView(preset: target.preset)
                .environment(viewModel)
        }
    }

    private var generationForm: some View {
        @Bindable var viewModel = viewModel
        return Form {
            Section {
                ProgressView(value: viewModel.contextInfo.usageRatio)
                    .tint(contextColor)
                LabeledContent(
                    "Токенов",
                    value: "\(viewModel.contextInfo.usedTokens.formatted()) / \(viewModel.contextInfo.contextLimit.formatted())"
                )
                LabeledContent(
                    "Reasoning",
                    value: viewModel.contextInfo.reasoningTokens.formatted()
                )
                LabeledContent(
                    "Подсчёт",
                    value: viewModel.contextInfo.isExact ? "точный" : "оценка"
                )
            } header: {
                Label("Контекст", systemImage: "gauge.with.dots.needle.33percent")
            } footer: {
                Text("Инструкции, история, tools и вложения занимают контекст следующего ответа.")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Случайность")
                        Spacer()
                        Text(viewModel.settings.temperature, format: .number.precision(.fractionLength(1)))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.settings.temperature, in: 0...2, step: 0.1)
                }

                Toggle("Ограничить длину ответа", isOn: $viewModel.settings.useMaxTokens)
                if viewModel.settings.useMaxTokens {
                    Stepper(
                        "\(viewModel.settings.maxTokens) токенов",
                        value: $viewModel.settings.maxTokens,
                        in: 64...32_768,
                        step: 64
                    )
                }
            } header: {
                Text("Стиль ответа")
            } footer: {
                Text("Низкая случайность делает ответы стабильнее; высокая — разнообразнее.")
            }

            Section {
                Picker("Рассуждение", selection: $viewModel.settings.reasoningLevel) {
                    ForEach(GenerationSettings.ReasoningLevel.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                .disabled(!viewModel.modelType.supportsReasoning)

                Toggle("Показывать рассуждение", isOn: $viewModel.settings.showReasoning)
                    .disabled(!viewModel.currentReadiness.supportsReasoning)
                Toggle("Показывать скорость (TK/s)", isOn: $viewModel.settings.showTokenSpeed)
            } header: {
                Label("Рассуждение", systemImage: "brain")
            } footer: {
                Text("Local не предоставляет управляемое reasoning. Доступные параметры зависят от выбранной модели.")
            }

            Section {
                Toggle("Распознавание текста (OCR)", isOn: .constant(false))
                    .disabled(true)
                Toggle("Штрихкоды и QR-коды", isOn: .constant(false))
                    .disabled(true)
                Toggle("Поиск по данным Mac", isOn: .constant(false))
                    .disabled(true)
                Toggle("Структурированный JSON", isOn: $viewModel.settings.guidedGeneration)
            } header: {
                Label("Инструменты", systemImage: "wrench.and.screwdriver")
            } footer: {
                Text("На iPhone OCR и QR работают через Vision-вложения. Системные tools и Spotlight RAG доступны только в macOS-версии.")
            }

            Section {
                if viewModel.toolEvents.isEmpty {
                    Text("Вызовов пока нет")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.toolEvents.prefix(6)) { event in
                        DisclosureGroup(event.name) {
                            Text(event.argumentsJSON)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            } header: {
                Label("Журнал инструментов", systemImage: "terminal")
            }

            Section {
                Button {
                    Task { await viewModel.runEvaluationSuite() }
                } label: {
                    if viewModel.isEvaluating {
                        HStack {
                            ProgressView()
                            Text("Проверки выполняются…")
                        }
                    } else {
                        Label("Запустить проверки", systemImage: "play.fill")
                    }
                }
                .disabled(
                    viewModel.isEvaluating
                    || viewModel.isProcessing
                    || !viewModel.currentReadiness.canGenerate
                )

                ForEach(viewModel.evaluationResults) { result in
                    DisclosureGroup {
                        Text(result.detail)
                            .font(.caption)
                            .textSelection(.enabled)
                    } label: {
                        Label(
                            "\(result.name) · \(result.duration.formatted(.number.precision(.fractionLength(2)))) с",
                            systemImage: result.passed
                                ? "checkmark.circle.fill"
                                : "xmark.circle.fill"
                        )
                        .foregroundStyle(result.passed ? .green : .red)
                    }
                }
            } header: {
                Label("Проверки качества", systemImage: "checklist.checked")
            }
        }
    }

    private var instructionsForm: some View {
        @Bindable var viewModel = viewModel
        return Form {
            Section {
                ForEach(viewModel.promptPresets) { preset in
                    Button {
                        viewModel.applyPrompt(preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name)
                                    .foregroundStyle(.primary)
                                Text(preset.isBuiltIn ? "Встроенный профиль" : "Пользовательский")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if preset.instructions == viewModel.settings.systemInstructions {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .contextMenu {
                        Button("Применить") { viewModel.applyPrompt(preset) }
                        if !preset.isBuiltIn {
                            Button("Изменить", systemImage: "pencil") {
                                promptEditorTarget = .edit(preset)
                            }
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                viewModel.deletePrompt(preset.id)
                            }
                        }
                    }
                    .swipeActions {
                        if !preset.isBuiltIn {
                            Button(role: .destructive) {
                                viewModel.deletePrompt(preset.id)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            Button {
                                promptEditorTarget = .edit(preset)
                            } label: {
                                Label("Изменить", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }

                Button {
                    promptEditorTarget = .create
                } label: {
                    Label("Создать свой промпт", systemImage: "plus")
                }
            } header: {
                Label("Библиотека промптов", systemImage: "text.book.closed")
            } footer: {
                Text("Профиль задаёт роль, тон и правила для новой сессии модели.")
            }

            Section {
                TextEditor(text: $viewModel.settings.systemInstructions)
                    .frame(minHeight: 220)
                Button("Вернуть стандартные инструкции") {
                    viewModel.resetInstructions()
                }
            } header: {
                Label("Активные инструкции", systemImage: "quote.bubble")
            } footer: {
                Text("Изменение инструкций создаёт новую AI-сессию, но сохраняет историю чата.")
            }
        }
    }

    private var modelsForm: some View {
        @Bindable var viewModel = viewModel
        return Form {
            Section {
                LabeledContent("Режим", value: viewModel.modelType.fullName)
                Text(
                    viewModel.modelType == .local
                        ? "Работает на \(MobilePlatform.deviceName) и доступна офлайн."
                        : "Модель Apple в Private Cloud Compute."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Label("Текущий режим", systemImage: viewModel.modelType.iconName)
            }

            Section {
                ForEach(ModelType.allCases) { type in
                    Button {
                        viewModel.selectModel(type)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: type.iconName)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.fullName)
                                    .foregroundStyle(.primary)
                                Text(viewModel.readiness[type]?.detail ?? "Проверяем…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                Text(
                                    "\((viewModel.readiness[type]?.contextLimit ?? 0).formatted()) токенов контекста"
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if viewModel.modelType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                Button("Проверить доступность снова") {
                    Task { await viewModel.checkAvailability() }
                }
            } header: {
                Text("Apple AI")
            } footer: {
                Text("Local использует SystemLanguageModel.default на \(MobilePlatform.deviceName). Для Cloud требуется managed entitlement Private Cloud Compute.")
            }

            Section {
                capability("Vision input", available: viewModel.currentReadiness.supportsVision)
                capability(
                    "Guided generation",
                    available: viewModel.currentReadiness.supportsGuidedGeneration
                )
                capability("Reasoning", available: viewModel.currentReadiness.supportsReasoning)
            } header: {
                Label("Возможности", systemImage: "sparkles.rectangle.stack")
            }

            Section {
                Label("OCR и QR доступны через анализ вложений Vision.", systemImage: "viewfinder")
                Label(
                    "Системные OCRTool и BarcodeReaderTool текущего iOS SDK не предоставляет.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            } header: {
                Text("Инструменты \(MobilePlatform.deviceName)")
            }

            Section {
                Button("Экспортировать диагностику", systemImage: "square.and.arrow.up") {
                    viewModel.exportDiagnostics()
                }
                if let url = viewModel.exportedFileURL {
                    ShareLink(item: url) {
                        Label("Поделиться экспортом", systemImage: "square.and.arrow.up")
                    }
                }
                LabeledContent("Foundation Models Instruments", value: "Запускается на Mac")
            } header: {
                Label("Диагностика", systemImage: "stethoscope")
            } footer: {
                Text("Экспорт не включает prompts, ответы, пути файлов и содержимое вложений.")
            }
        }
    }

    private var contextColor: Color {
        if viewModel.contextInfo.usageRatio > 0.85 { return .red }
        if viewModel.contextInfo.usageRatio > 0.65 { return .orange }
        return .green
    }

    private func capability(_ title: String, available: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}

private struct MobilePromptEditorView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    let preset: PromptPreset?
    @State private var name: String
    @State private var instructions: String

    init(preset: PromptPreset?) {
        self.preset = preset
        _name = State(initialValue: preset?.name ?? "")
        _instructions = State(initialValue: preset?.instructions ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например, Редактор текста", text: $name)
                }
                Section {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 260)
                } header: {
                    Text("Инструкции")
                } footer: {
                    Text("Промпт сохраняется только на этом устройстве.")
                }
            }
            .navigationTitle(preset == nil ? "Новый промпт" : "Изменить промпт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if let preset {
                            viewModel.updatePrompt(
                                preset.id,
                                name: name,
                                instructions: instructions
                            )
                        } else {
                            viewModel.addPrompt(name: name, instructions: instructions)
                        }
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}

struct MobileAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        Text("Foundation Chat")
                            .font(.title.bold())
                        Text("Apple Intelligence research playground")
                            .foregroundStyle(.secondary)
                    }

                    Text("Кроссплатформенный полигон для Apple Foundation Models на Mac, iPhone и iPad.")
                        .multilineTextAlignment(.center)

                    Link(
                        "Открыть репозиторий на GitHub",
                        destination: URL(string: "https://github.com/pavelrakcheev/FoundationChat")!
                    )
                    .buttonStyle(.glassProminent)

                    Text(
                        "Создан совместно Павлом Ракчеевым, DeepSeek v4 Flash "
                        + "(Max Reasoning) в OpenCode Desktop и GPT‑5.6 Sol High "
                        + "в ChatGPT Codex."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(28)
            }
            .navigationTitle("О проекте")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
#endif
