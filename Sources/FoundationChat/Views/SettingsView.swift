import SwiftUI

enum InspectorSection: String, CaseIterable, Identifiable {
    case generation = "Ответ"
    case instructions = "Инструкции"
    case models = "Модель"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generation: "Генерация ответа"
        case .instructions: "Инструкции модели"
        case .models: "Модели Apple"
        }
    }

    var explanation: String {
        switch self {
        case .generation:
            "Стиль, длина ответа, инструменты и проверки качества."
        case .instructions:
            "Системные правила, которым модель следует в этом чате."
        case .models:
            "Доступность Local и Cloud, их возможности и ограничения."
        }
    }
}

struct SettingsInspectorView: View {
    @Binding var selection: InspectorSection

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                Divider()
                inspectorContent
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            Picker("Раздел", selection: $selection) {
                ForEach(InspectorSection.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch selection {
        case .generation:
            GenerationInspector()
        case .instructions:
            InstructionsInspector()
        case .models:
            ModelsInspector()
        }
    }
}

// MARK: - Generation

private struct GenerationInspector: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            contextSection

            Section {
                Slider(value: $viewModel.settings.temperature, in: 0...2, step: 0.1)
                    .labelsHidden()

                Text("Случайность: \(viewModel.settings.temperature, format: .number.precision(.fractionLength(1))) — чем выше, тем разнообразнее")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Ограничить длину ответа", isOn: $viewModel.settings.useMaxTokens)
                if viewModel.settings.useMaxTokens {
                    Stepper(
                        "\(viewModel.settings.maxTokens.formatted()) токенов",
                        value: $viewModel.settings.maxTokens,
                        in: 64...32_768,
                        step: 64
                    )
                }
            } header: {
                Label("Стиль ответа", systemImage: "slider.horizontal.3")
            }
            .listRowInsets(EdgeInsets())

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
            }

            Section {
                Toggle("Распознавание текста (OCR)", isOn: $viewModel.settings.enableOCR)
                Toggle("Штрихкоды и QR-коды", isOn: $viewModel.settings.enableBarcodeReader)
                Toggle("Поиск по данным Mac", isOn: $viewModel.settings.enableSpotlightRAG)
                Toggle("Структурированный JSON", isOn: $viewModel.settings.guidedGeneration)
            } header: {
                Label("Инструменты", systemImage: "wrench.and.screwdriver")
            } footer: {
                Text("Изменение набора tools создаёт новую сессию, но история сохраняется.")
                    .font(.caption)
            }

            Section {
                if viewModel.toolEvents.isEmpty {
                    ContentUnavailableView {
                        Label("Вызовов пока нет", systemImage: "wrench")
                    } description: {
                        Text("Поятся после использования OCR, Barcode или Spotlight.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
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
                            ProgressView().controlSize(.mini)
                            Text("Выполняются…")
                        }
                    } else {
                        Label("Запустить проверки", systemImage: "play.fill")
                    }
                }
                .disabled(viewModel.isEvaluating || viewModel.isProcessing || !viewModel.currentReadiness.canGenerate)

                ForEach(viewModel.evaluationResults) { result in
                    DisclosureGroup {
                        Text(result.detail).font(.caption).textSelection(.enabled)
                    } label: {
                        Label(
                            "\(result.name) · \(result.duration.formatted(.number.precision(.fractionLength(2)))) с",
                            systemImage: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(result.passed ? .green : .red)
                    }
                }
            } header: {
                Label("Проверки качества", systemImage: "checklist.checked")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var contextSection: some View {
        Section {
            Gauge(value: viewModel.contextInfo.usageRatio) {
                Text("Использовано \(viewModel.contextInfo.usedTokens.formatted()) / \(viewModel.contextInfo.contextLimit.formatted())")
                    .font(.caption)
            }
            .tint(contextColor)
            .gaugeStyle(.linearCapacity)

            LabeledContent("Токенов", value: "\(viewModel.contextInfo.usedTokens.formatted()) / \(viewModel.contextInfo.contextLimit.formatted())")
            LabeledContent("Reasoning", value: viewModel.contextInfo.reasoningTokens.formatted())
        } header: {
            Label("Контекст", systemImage: "gauge.with.dots.needle.33percent")
        }
    }

    private var contextColor: Color {
        if viewModel.contextInfo.usageRatio > 0.85 { return .red }
        if viewModel.contextInfo.usageRatio > 0.65 { return .orange }
        return .green
    }
}

// MARK: - Instructions

private struct InstructionsInspector: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var showEditor = false
    @State private var editingPreset: PromptPreset?

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                ForEach(viewModel.promptPresets) { preset in
                    Button {
                        viewModel.applyPrompt(preset)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.isBuiltIn ? "sparkles" : "text.document")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(preset.isBuiltIn ? "Предложенный" : "Пользовательский")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if preset.instructions == viewModel.settings.systemInstructions {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Применить") { viewModel.applyPrompt(preset) }
                        if !preset.isBuiltIn {
                            Button("Изменить", systemImage: "pencil") {
                                editingPreset = preset
                                showEditor = true
                            }
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                viewModel.deletePrompt(preset.id)
                            }
                        }
                    }
                }

                Button {
                    editingPreset = nil
                    showEditor = true
                } label: {
                    Label("Создать свой промпт", systemImage: "plus")
                }
                .buttonStyle(.plain)
            } header: {
                Label("Библиотека промптов", systemImage: "text.book.closed")
            }

            Section {
                TextEditor(text: $viewModel.settings.systemInstructions)
                    .font(.callout)
                    .frame(minHeight: 140)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(.separator)
                    }

                Label(
                    "Изменения применятся к следующему запросу.",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Label("Активные инструкции", systemImage: "quote.bubble")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showEditor) {
            PromptEditorView(preset: editingPreset)
                .environment(viewModel)
        }
    }
}

// MARK: - Models

private struct ModelsInspector: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: viewModel.modelType.iconName)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.modelType.fullName)
                            .font(.headline)
                        Text(
                            viewModel.modelType == .local
                                ? "Работает на Mac, доступна офлайн."
                                : "Модель Apple в Private Cloud Compute."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Label("Текущий режим", systemImage: viewModel.modelType.iconName)
            }

            Section {
                ForEach(ModelType.allCases) { type in
                    let rd = viewModel.readiness[type] ?? .checking(for: type)
                    ModelReadinessRow(type: type, readiness: rd)
                }
            } header: {
                Label("Доступность моделей", systemImage: "checkmark.seal")
            }

            Section {
                CapabilityRow(title: "Изображения", available: viewModel.currentReadiness.supportsVision)
                CapabilityRow(title: "Структурированный ответ", available: viewModel.currentReadiness.supportsGuidedGeneration)
                CapabilityRow(title: "Reasoning", available: viewModel.currentReadiness.supportsReasoning)
            } header: {
                Label("Возможности", systemImage: "sparkles.rectangle.stack")
            }

            Section {
                Button("Проверить доступность", systemImage: "arrow.clockwise") {
                    Task { await viewModel.checkAvailability() }
                }
                Button("Instruments", systemImage: "waveform.path.ecg") {
                    viewModel.openFoundationModelsInstruments()
                }
                Button("Экспортировать диагностику", systemImage: "square.and.arrow.up") {
                    viewModel.exportDiagnostics()
                }
            } header: {
                Label("Диагностика", systemImage: "stethoscope")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Supporting Views

private struct ModelReadinessRow: View {
    let type: ModelType
    let readiness: ModelReadiness

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: type.iconName)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(type.fullName)
                    .font(.callout.weight(.medium))
                Text(readiness.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(readiness.contextLimit.formatted()) токенов контекста")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            readinessIcon
        }
    }

    @ViewBuilder
    private var readinessIcon: some View {
        switch readiness.state {
        case .checking:
            ProgressView()
                .controlSize(.mini)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .requiresSetup:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .unavailable:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct CapabilityRow: View {
    let title: String
    let available: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}

// MARK: - About

struct AboutProjectView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)

            VStack(spacing: 5) {
                Text("Foundation Chat")
                    .font(.title.bold())
                Text("Apple Intelligence research playground")
                    .foregroundStyle(.secondary)
            }

            Text(
                "Полигон для тестирования Apple Foundation Models, "
                + "Private Cloud Compute и системных AI API."
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: 430)

            Link(
                "Открыть репозиторий на GitHub",
                destination: URL(
                    string: "https://github.com/pavelrakcheev/FoundationChat"
                )!
            )
            .buttonStyle(.link)

            Text(
                "Создан совместно Павлом Ракчеевым, DeepSeek v4 Flash "
                + "(Max Reasoning) в OpenCode Desktop и GPT‑5.6 Sol High "
                + "в ChatGPT Codex."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
        }
        .padding(28)
        .frame(width: 540, height: 440)
    }
}

// MARK: - Prompt Editor

private struct PromptEditorView: View {
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset == nil ? "Новый промпт" : "Изменить промпт")
                    .font(.title2.bold())
                Text("Название и инструкции сохраняются только на этом Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("Название", text: $name)
            TextEditor(text: $instructions)
                .font(.body)
                .frame(minHeight: 260)
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.separator)
                }

            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                Button("Сохранить") {
                    if let preset {
                        viewModel.updatePrompt(preset.id, name: name, instructions: instructions)
                    } else {
                        viewModel.addPrompt(name: name, instructions: instructions)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(22)
        .frame(width: 540, height: 440)
    }
}
