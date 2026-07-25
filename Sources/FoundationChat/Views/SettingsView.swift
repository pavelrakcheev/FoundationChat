import SwiftUI

enum InspectorSection: String, CaseIterable, Identifiable {
    case generation = "Генерация"
    case instructions = "Инструкции"
    case models = "Модели"

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
            "Управляйте стилем ответа, системными инструментами и проверками качества."
        case .instructions:
            "Задайте постоянные правила, которым модель будет следовать в этом чате."
        case .models:
            "Проверьте доступность Local и Cloud, их возможности и ограничения."
        }
    }
}

struct SettingsInspectorView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var selection: InspectorSection

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                inspectorHeader
                Divider()
                inspectorContent
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Раздел", selection: $selection) {
                ForEach(InspectorSection.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .font(.headline)
                Text(selection.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

private struct GenerationInspector: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            LazyVStack(spacing: 14) {
                responseStyle(settings: $viewModel.settings)
                reasoningAndMetrics(settings: $viewModel.settings)
                contextUsage
                modelTools(settings: $viewModel.settings)
                toolCallingLog
                evaluations
            }
            .padding(16)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .controlSize(.small)
    }

    private func responseStyle(
        settings: Binding<GenerationSettings>
    ) -> some View {
        InspectorGroup(
            title: "Стиль ответа",
            systemImage: "slider.horizontal.3",
            explanation: "Эти параметры меняют вариативность и максимальный размер следующего ответа."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                LabeledContent("Случайность") {
                    Text(
                        settings.wrappedValue.temperature.formatted(
                            .number.precision(.fractionLength(1))
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }

                Slider(
                    value: settings.temperature,
                    in: 0...2,
                    step: 0.1
                )

                Text("Ниже — стабильнее и точнее. Выше — разнообразнее и менее предсказуемо.")
                    .inspectorHelpStyle()

                Divider()

                Toggle("Ограничить длину ответа", isOn: settings.useMaxTokens)
                Text("Полезно, когда нужен короткий результат или важно экономить контекст.")
                    .inspectorHelpStyle()

                if settings.wrappedValue.useMaxTokens {
                    Stepper(
                        "\(settings.wrappedValue.maxTokens.formatted()) токенов",
                        value: settings.maxTokens,
                        in: 64...32_768,
                        step: 64
                    )
                }
            }
        }
    }

    private func reasoningAndMetrics(
        settings: Binding<GenerationSettings>
    ) -> some View {
        InspectorGroup(
            title: "Рассуждение и скорость",
            systemImage: "brain",
            explanation: "Cloud умеет выделять больше вычислений на сложную задачу. Local отвечает без управляемого reasoning."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Глубина рассуждения", selection: settings.reasoningLevel) {
                    ForEach(GenerationSettings.ReasoningLevel.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                .disabled(!viewModel.modelType.supportsReasoning)

                if !viewModel.currentReadiness.supportsReasoning {
                    Label(
                        "Текущая модель не предоставляет reasoning transcript.",
                        systemImage: "info.circle"
                    )
                    .inspectorHelpStyle()
                }

                Divider()

                Toggle("Показывать ход рассуждения", isOn: settings.showReasoning)
                    .disabled(!viewModel.currentReadiness.supportsReasoning)
                Text("Показывает только тот reasoning, который модель явно возвращает через API.")
                    .inspectorHelpStyle()

                Divider()

                Toggle("Показывать скорость", isOn: settings.showTokenSpeed)
                Text("TK/s — сколько видимых токенов ответа модель генерирует за секунду.")
                    .inspectorHelpStyle()
            }
        }
    }

    private var contextUsage: some View {
        InspectorGroup(
            title: "Контекст текущего чата",
            systemImage: "gauge.with.dots.needle.33percent",
            explanation: "Контекст включает инструкции, историю, tools, вложения и место для нового ответа."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: viewModel.contextInfo.usageRatio)
                    .tint(contextColor)

                LabeledContent(
                    "Использовано",
                    value: "\(viewModel.contextInfo.usedTokens.formatted()) / "
                        + viewModel.contextInfo.contextLimit.formatted()
                )
                LabeledContent(
                    "Reasoning-токены",
                    value: viewModel.contextInfo.reasoningTokens.formatted()
                )
                LabeledContent(
                    "Точность подсчёта",
                    value: viewModel.contextInfo.isExact ? "точно" : "оценка"
                )

                Text("Когда шкала заполнится, старую историю потребуется сократить или суммировать.")
                    .inspectorHelpStyle()
            }
        }
    }

    private func modelTools(
        settings: Binding<GenerationSettings>
    ) -> some View {
        InspectorGroup(
            title: "Системные инструменты",
            systemImage: "wrench.and.screwdriver",
            explanation: "Tools дают модели проверяемые функции вместо попытки угадать результат."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ExplainedToggle(
                    title: "Распознавание текста",
                    explanation: "OCRTool читает текст на изображениях через системный Vision.",
                    isOn: settings.enableOCR
                )
                Divider()
                ExplainedToggle(
                    title: "Штрихкоды и QR-коды",
                    explanation: "BarcodeReaderTool извлекает содержимое кодов с изображения.",
                    isOn: settings.enableBarcodeReader
                )
                Divider()
                ExplainedToggle(
                    title: "Поиск по данным Mac",
                    explanation: "Spotlight RAG ищет только локально проиндексированные материалы.",
                    isOn: settings.enableSpotlightRAG
                )
                Divider()
                ExplainedToggle(
                    title: "Структурированный JSON",
                    explanation: "Guided generation заставляет ответ соответствовать типизированной схеме.",
                    isOn: settings.guidedGeneration
                )

                Text("Изменение набора tools создаёт новую модельную сессию, но сообщения чата сохраняются.")
                    .inspectorHelpStyle()
                    .padding(.top, 2)
            }
        }
    }

    private var toolCallingLog: some View {
        InspectorGroup(
            title: "Журнал инструментов",
            systemImage: "terminal",
            explanation: "Здесь видно, какой tool вызвала модель и какие аргументы ему передала."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.toolEvents.isEmpty {
                    ContentUnavailableView {
                        Label("Вызовов пока нет", systemImage: "wrench")
                    } description: {
                        Text("Записи появятся после использования OCR, Barcode или Spotlight.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(viewModel.toolEvents.prefix(6)) { event in
                        DisclosureGroup(event.name) {
                            Text(event.argumentsJSON)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                        }
                    }
                }

                Text("Встроенные tools только читают данные. Изменяющие систему действия не зарегистрированы.")
                    .inspectorHelpStyle()
            }
        }
    }

    private var evaluations: some View {
        InspectorGroup(
            title: "Проверки качества",
            systemImage: "checklist.checked",
            explanation: "Smoke suite отправляет контрольные prompts и показывает, сохранилось ли ожидаемое поведение."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                Button {
                    Task {
                        await viewModel.runEvaluationSuite()
                    }
                } label: {
                    if viewModel.isEvaluating {
                        HStack {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Выполняются проверки…")
                        }
                    } else {
                        Label("Запустить быстрые проверки", systemImage: "play.fill")
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
                            "\(result.name) · "
                                + result.duration.formatted(
                                    .number.precision(.fractionLength(2))
                                )
                                + " с",
                            systemImage: result.passed
                                ? "checkmark.circle.fill"
                                : "xmark.circle.fill"
                        )
                        .foregroundStyle(result.passed ? .green : .red)
                    }
                }
            }
        }
    }

    private var contextColor: Color {
        if viewModel.contextInfo.usageRatio > 0.85 {
            return .red
        }
        if viewModel.contextInfo.usageRatio > 0.65 {
            return .orange
        }
        return .green
    }
}

private struct InstructionsInspector: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var showEditor = false
    @State private var editingPreset: PromptPreset?

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            LazyVStack(spacing: 14) {
                promptLibrary
                activeInstructions(instructions: $viewModel.settings.systemInstructions)
            }
            .padding(16)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .sheet(isPresented: $showEditor) {
            PromptEditorView(preset: editingPreset)
                .environment(viewModel)
        }
    }

    private var promptLibrary: some View {
        InspectorGroup(
            title: "Библиотека промптов",
            systemImage: "text.book.closed",
            explanation: "Preset быстро заменяет активные инструкции. Встроенные варианты можно применять, а свои — редактировать."
        ) {
            VStack(spacing: 4) {
                ForEach(viewModel.promptPresets) { preset in
                    Button {
                        viewModel.applyPrompt(preset)
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName: preset.isBuiltIn
                                    ? "sparkles"
                                    : "text.document"
                            )
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
                        .padding(.vertical, 5)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Применить") {
                            viewModel.applyPrompt(preset)
                        }
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

                Divider()
                    .padding(.vertical, 3)

                Button {
                    editingPreset = nil
                    showEditor = true
                } label: {
                    Label("Создать свой промпт", systemImage: "plus")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func activeInstructions(
        instructions: Binding<String>
    ) -> some View {
        InspectorGroup(
            title: "Активные инструкции",
            systemImage: "quote.bubble",
            explanation: "Это постоянный контекст для модели: роль, стиль, правила и границы поведения."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                TextEditor(text: instructions)
                    .font(.callout)
                    .frame(minHeight: 260)
                    .padding(6)
                    .background(.background, in: .rect(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(.separator)
                    }

                Label(
                    "Изменения применятся к следующему запросу. История сообщений не удаляется.",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                )
                .inspectorHelpStyle()
            }
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
                .padding(6)
                .background(.background, in: .rect(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.separator)
                }

            HStack {
                Spacer()
                Button("Отмена", role: .cancel) {
                    dismiss()
                }
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
                .buttonStyle(.borderedProminent)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || instructions.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }
        }
        .padding(22)
        .frame(width: 540, height: 440)
    }
}

private struct ModelsInspector: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                currentModel
                modelAvailability
                capabilities
                diagnostics
            }
            .padding(16)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .controlSize(.small)
    }

    private var currentModel: some View {
        InspectorGroup(
            title: "Текущий режим",
            systemImage: viewModel.modelType.iconName,
            explanation: "Модель выбирается рядом с полем ввода и сохраняется отдельно для каждого чата."
        ) {
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
                            ? "Работает на Mac, доступна офлайн и не отправляет prompt в облако."
                            : "Большая модель Apple в Private Cloud Compute с reasoning и контекстом 32K."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var modelAvailability: some View {
        InspectorGroup(
            title: "Доступность моделей Apple",
            systemImage: "checkmark.seal",
            explanation: "Foundation Chat намеренно не показывает сторонние или open-source модели."
        ) {
            VStack(spacing: 10) {
                ForEach(ModelType.allCases) { type in
                    ModelReadinessRow(
                        type: type,
                        readiness: viewModel.readiness[type] ?? .checking(for: type)
                    )

                    if type != ModelType.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    private var capabilities: some View {
        InspectorGroup(
            title: "Возможности текущей модели",
            systemImage: "sparkles.rectangle.stack",
            explanation: "Поддержка определяется в runtime: она может меняться после обновления macOS."
        ) {
            VStack(spacing: 10) {
                CapabilityRow(
                    title: "Анализ изображений",
                    explanation: "Можно прикладывать изображения к prompt.",
                    available: viewModel.currentReadiness.supportsVision
                )
                Divider()
                CapabilityRow(
                    title: "Структурированный ответ",
                    explanation: "Модель может генерировать данные по схеме.",
                    available: viewModel.currentReadiness.supportsGuidedGeneration
                )
                Divider()
                CapabilityRow(
                    title: "Reasoning transcript",
                    explanation: "API возвращает отдельные reasoning-данные.",
                    available: viewModel.currentReadiness.supportsReasoning
                )
            }
        }
    }

    private var diagnostics: some View {
        InspectorGroup(
            title: "Диагностика",
            systemImage: "stethoscope",
            explanation: "Инструменты помогают проверить доступность модели и подготовить безопасный отчёт об ошибке."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                Button("Проверить доступность снова", systemImage: "arrow.clockwise") {
                    Task {
                        await viewModel.checkAvailability()
                    }
                }
                Button("Открыть Foundation Models Instruments", systemImage: "waveform.path.ecg") {
                    viewModel.openFoundationModelsInstruments()
                }
                Button("Экспортировать диагностику", systemImage: "square.and.arrow.up") {
                    viewModel.exportDiagnostics()
                }

                Text("Экспорт по умолчанию не содержит prompts, ответов, путей к файлам и вложений.")
                    .inspectorHelpStyle()
            }
        }
    }
}

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
        .padding(.vertical, 2)
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
    let explanation: String
    let available: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                available ? "Да" : "Нет",
                systemImage: available ? "checkmark.circle.fill" : "minus.circle"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(available ? .green : .secondary)
        }
    }
}

private struct ExplainedToggle: View {
    let title: String
    let explanation: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: $isOn)
            Text(explanation)
                .inspectorHelpStyle()
        }
    }
}

private struct InspectorGroup<Content: View>: View {
    let title: String
    let systemImage: String
    let explanation: String
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        explanation: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.explanation = explanation
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

private extension View {
    func inspectorHelpStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
