import SwiftUI

enum InspectorSection: String, CaseIterable, Identifiable {
    case generation = "Генерация"
    case instructions = "Инструкции"
    case models = "Модели"
    var id: String { rawValue }
}

struct SettingsInspectorView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var selection: InspectorSection

    var body: some View {
        VStack(spacing: 0) {
            Picker("Раздел", selection: $selection) {
                ForEach(InspectorSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            switch selection {
            case .generation:
                GenerationInspector()
            case .instructions:
                InstructionsInspector()
            case .models:
                ModelsInspector()
            }
        }
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        .task { await viewModel.checkAvailability() }
    }
}

private struct GenerationInspector: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section("Ответ") {
                LabeledContent(
                    "Temperature",
                    value: viewModel.settings.temperature.formatted(
                        .number.precision(.fractionLength(1))
                    )
                )
                Slider(value: $viewModel.settings.temperature, in: 0...2, step: 0.1)
                Toggle("Ограничить длину", isOn: $viewModel.settings.useMaxTokens)
                if viewModel.settings.useMaxTokens {
                    Stepper(
                        "\(viewModel.settings.maxTokens.formatted()) токенов",
                        value: $viewModel.settings.maxTokens,
                        in: 64...32_768,
                        step: 64
                    )
                }
            }

            Section("Reasoning и метрики") {
                Picker("Глубина", selection: $viewModel.settings.reasoningLevel) {
                    ForEach(GenerationSettings.ReasoningLevel.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                .disabled(!viewModel.modelType.supportsReasoning)
                Toggle("Показывать рассуждение", isOn: $viewModel.settings.showReasoning)
                Toggle("Показывать скорость TK/s", isOn: $viewModel.settings.showTokenSpeed)
                if !viewModel.currentReadiness.supportsReasoning {
                    Text("Текущая модель не отдаёт reasoning transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Контекст") {
                ProgressView(value: viewModel.contextInfo.usageRatio)
                    .tint(contextColor)
                LabeledContent(
                    "Использовано",
                    value: "\(viewModel.contextInfo.usedTokens.formatted()) / \(viewModel.contextInfo.contextLimit.formatted())"
                )
                LabeledContent(
                    "Reasoning",
                    value: "\(viewModel.contextInfo.reasoningTokens.formatted())"
                )
                LabeledContent("Подсчёт", value: viewModel.contextInfo.isExact ? "точный" : "оценка")
            }

            Section("Apple AI Lab") {
                Toggle("OCRTool", isOn: $viewModel.settings.enableOCR)
                Toggle("BarcodeReaderTool", isOn: $viewModel.settings.enableBarcodeReader)
                Toggle("Локальный RAG · Spotlight", isOn: $viewModel.settings.enableSpotlightRAG)
                Toggle("Guided generation", isOn: $viewModel.settings.guidedGeneration)
                Text("Изменение tools создаёт новую сессию, transcript чата сохраняется.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tool calling lab") {
                if viewModel.toolEvents.isEmpty {
                    Text("Вызовов пока нет. OCR, Barcode и Spotlight появятся здесь после использования моделью.")
                        .font(.caption)
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
                Text("Встроенные Apple tools только читают данные; опасные изменяющие действия не зарегистрированы.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("Evaluations") {
                Button {
                    Task { await viewModel.runEvaluationSuite() }
                } label: {
                    if viewModel.isEvaluating {
                        HStack {
                            ProgressView().controlSize(.mini)
                            Text("Выполняются тесты…")
                        }
                    } else {
                        Label("Запустить smoke suite", systemImage: "checklist")
                    }
                }
                .disabled(
                    viewModel.isEvaluating || viewModel.isProcessing
                        || !viewModel.currentReadiness.canGenerate
                )

                ForEach(viewModel.evaluationResults) { result in
                    DisclosureGroup {
                        Text(result.detail).font(.caption).textSelection(.enabled)
                    } label: {
                        Label(
                            "\(result.name) · \(result.duration, format: .number.precision(.fractionLength(2))) с",
                            systemImage: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(result.passed ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var contextColor: Color {
        if viewModel.contextInfo.usageRatio > 0.85 { return .red }
        if viewModel.contextInfo.usageRatio > 0.65 { return .orange }
        return .green
    }
}

private struct InstructionsInspector: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var selectedPresetID: UUID?
    @State private var showEditor = false
    @State private var editingPreset: PromptPreset?

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            List(selection: $selectedPresetID) {
                Section("Список промптов") {
                    ForEach(viewModel.promptPresets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).lineLimit(1)
                                if preset.isBuiltIn {
                                    Text("Предложенный").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if preset.instructions == viewModel.settings.systemInstructions {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .tag(preset.id)
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
                }
            }
            .frame(minHeight: 160, maxHeight: 230)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Активные инструкции").font(.headline)
                    Spacer()
                    Button("Новый", systemImage: "plus") {
                        editingPreset = nil
                        showEditor = true
                    }
                    .labelStyle(.iconOnly)
                }

                TextEditor(text: $viewModel.settings.systemInstructions)
                    .font(.callout)
                    .frame(minHeight: 220)
                    .padding(5)
                    .background(.background, in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).stroke(.separator)
                    }

                Text("Изменение применится к следующему запросу без удаления истории.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .onChange(of: selectedPresetID) { _, id in
            guard let id, let preset = viewModel.promptPresets.first(where: { $0.id == id }) else {
                return
            }
            viewModel.applyPrompt(preset)
        }
        .sheet(isPresented: $showEditor) {
            PromptEditorView(preset: editingPreset)
                .environment(viewModel)
        }
    }
}

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
            Text(preset == nil ? "Новый промпт" : "Изменить промпт")
                .font(.title2.bold())
            TextField("Название", text: $name)
            TextEditor(text: $instructions)
                .font(.body)
                .frame(minHeight: 260)
                .padding(6)
                .background(.background, in: .rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(.separator) }
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
        .frame(width: 520, height: 410)
    }
}

private struct ModelsInspector: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        Form {
            Section("Только модели Apple") {
                ForEach(ModelType.allCases) { type in
                    ModelReadinessRow(
                        type: type,
                        readiness: viewModel.readiness[type] ?? .checking(for: type)
                    )
                }
            }

            Section("Возможности текущей модели") {
                CapabilityRow(
                    title: "Vision input",
                    available: viewModel.currentReadiness.supportsVision
                )
                CapabilityRow(
                    title: "Guided generation",
                    available: viewModel.currentReadiness.supportsGuidedGeneration
                )
                CapabilityRow(
                    title: "Reasoning transcript",
                    available: viewModel.currentReadiness.supportsReasoning
                )
            }

            Section("Диагностика") {
                Button("Проверить доступность снова") {
                    Task { await viewModel.checkAvailability() }
                }
                Button("Открыть Instruments", systemImage: "waveform.path.ecg") {
                    viewModel.openFoundationModelsInstruments()
                }
                Button("Экспортировать диагностику", systemImage: "square.and.arrow.up") {
                    viewModel.exportDiagnostics()
                }
                Text("Экспорт по умолчанию не содержит prompts, ответов, путей и вложений.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelReadinessRow: View {
    let type: ModelType
    let readiness: ModelReadiness

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: type.iconName).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(type.fullName).font(.callout.weight(.medium))
                Text(readiness.detail).font(.caption).foregroundStyle(.secondary)
                Text("\(readiness.contextLimit.formatted()) токенов")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            switch readiness.state {
            case .checking: ProgressView().controlSize(.mini)
            case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .requiresSetup:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .unavailable: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct CapabilityRow: View {
    let title: String
    let available: Bool

    var body: some View {
        LabeledContent(title) {
            Label(
                available ? "Да" : "Нет",
                systemImage: available ? "checkmark.circle.fill" : "minus.circle"
            )
            .foregroundStyle(available ? .green : .secondary)
        }
    }
}

struct AboutProjectView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            VStack(spacing: 5) {
                Text("Foundation Chat").font(.title.bold())
                Text("Apple Intelligence research playground").foregroundStyle(.secondary)
            }
            Text(
                "Полигон для тестирования Apple Foundation Models, Private Cloud Compute и Core AI."
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: 430)
            Link(
                "github.com/pavelrakcheev/FoundationChat",
                destination: URL(string: "https://github.com/pavelrakcheev/FoundationChat")!
            )
            Text(
                "Создан совместно Павлом Ракчеевым, DeepSeek v4 Flash (Max Reasoning) в OpenCode Desktop и GPT‑5.6 Sol High в ChatGPT Codex."
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
