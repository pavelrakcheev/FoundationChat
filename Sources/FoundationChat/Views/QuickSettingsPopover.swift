import SwiftUI

struct QuickSettingsPopover: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var selection: InspectorSection
    @Binding var fullInspectorPresented: Bool
    let closePopover: () -> Void

    @State private var showAdvanced = false

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            header

            Picker("Раздел параметров", selection: $selection) {
                ForEach(InspectorSection.allCases) { section in
                    Text(section.rawValue)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch selection {
                case .generation:
                    responseSettings(settings: $viewModel.settings)
                case .instructions:
                    instructionSettings
                case .models:
                    modelSettings
                }
            }
            .padding(14)

            Divider()

            Button {
                let shouldOpen = !fullInspectorPresented
                closePopover()
                fullInspectorPresented = shouldOpen
            } label: {
                Text(
                    fullInspectorPresented
                        ? "Закрыть все параметры"
                        : "Открыть все параметры…"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(12)
        }
        .frame(width: 360)
        .controlSize(.small)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Параметры ответа")
                    .font(.headline)

                Text(
                    "\(viewModel.modelType.shortName) · "
                        + "\(viewModel.contextInfo.usedTokens.formatted()) / "
                        + viewModel.contextInfo.contextLimit.formatted()
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer()

            Menu {
                Button("Сбросить параметры ответа", systemImage: "arrow.counterclockwise") {
                    resetResponseSettings()
                }
                Divider()
                Button("Проверить модель", systemImage: "arrow.clockwise") {
                    Task {
                        await viewModel.refreshAvailability(for: viewModel.modelType)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .help("Дополнительные действия")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func responseSettings(
        settings: Binding<GenerationSettings>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Случайность") {
                Text(
                    settings.wrappedValue.temperature.formatted(
                        .number.precision(.fractionLength(1))
                    )
                )
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Slider(
                value: settings.temperature,
                in: 0...2,
                step: 0.1
            )

            HStack {
                Text("Точнее")
                Spacer()
                Text("Креативнее")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Divider()

            Picker("Длина", selection: settings.useMaxTokens) {
                Text("Автоматически").tag(false)
                Text("Ограничить").tag(true)
            }
            .pickerStyle(.menu)

            if settings.wrappedValue.useMaxTokens {
                Stepper(
                    "\(settings.wrappedValue.maxTokens.formatted()) токенов",
                    value: settings.maxTokens,
                    in: 64...32_768,
                    step: 64
                )
            }

            Divider()

            Toggle("Показывать скорость", isOn: settings.showTokenSpeed)

            Divider()

            DisclosureGroup(isExpanded: $showAdvanced) {
                advancedSettings(settings: settings)
                    .padding(.top, 10)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Дополнительно")
                    Text("Рассуждение, инструменты и диагностика")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func advancedSettings(
        settings: Binding<GenerationSettings>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.currentReadiness.supportsReasoning {
                Picker("Рассуждение", selection: settings.reasoningLevel) {
                    ForEach(GenerationSettings.ReasoningLevel.allCases) { level in
                        Text(level.displayName)
                            .tag(level)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Показывать ход рассуждения", isOn: settings.showReasoning)
            } else {
                Label(
                    "Reasoning недоступен для \(viewModel.modelType.shortName)",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle("Распознавание текста", isOn: settings.enableOCR)
            Toggle("Штрихкоды и QR", isOn: settings.enableBarcodeReader)
            Toggle("Поиск Spotlight", isOn: settings.enableSpotlightRAG)
            Toggle("Структурированный JSON", isOn: settings.guidedGeneration)
        }
    }

    private var instructionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Профиль")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(viewModel.promptPresets) { preset in
                    Button {
                        viewModel.applyPrompt(preset)
                    } label: {
                        if preset.instructions == viewModel.settings.systemInstructions {
                            Label(preset.name, systemImage: "checkmark")
                        } else {
                            Text(preset.name)
                        }
                    }
                }
            } label: {
                HStack {
                    Label(activePromptName, systemImage: "text.quote")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)

            Divider()

            Text(viewModel.settings.systemInstructions)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .textSelection(.enabled)

            Label(
                "Изменения применяются к следующему запросу.",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                "Модель",
                selection: Binding(
                    get: { viewModel.modelType },
                    set: { viewModel.selectModel($0) }
                )
            ) {
                ForEach(ModelType.allCases) { type in
                    Label(type.shortName, systemImage: type.iconName)
                        .tag(type)
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.isProcessing)

            Divider()

            HStack(alignment: .top, spacing: 9) {
                readinessSymbol

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.modelType.fullName)
                        .font(.callout.weight(.medium))
                    Text(viewModel.currentReadiness.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            capabilityRow(
                "Изображения",
                available: viewModel.currentReadiness.supportsVision
            )
            capabilityRow(
                "Структурированный ответ",
                available: viewModel.currentReadiness.supportsGuidedGeneration
            )
            capabilityRow(
                "Reasoning",
                available: viewModel.currentReadiness.supportsReasoning
            )
        }
    }

    @ViewBuilder
    private var readinessSymbol: some View {
        switch viewModel.currentReadiness.state {
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

    private func capabilityRow(
        _ title: String,
        available: Bool
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(
                systemName: available
                    ? "checkmark.circle.fill"
                    : "minus.circle"
            )
            .foregroundStyle(available ? .green : .secondary)
            .accessibilityLabel(available ? "Доступно" : "Недоступно")
        }
    }

    private var activePromptName: String {
        viewModel.promptPresets.first {
            $0.instructions == viewModel.settings.systemInstructions
        }?.name ?? "Пользовательский"
    }

    private func resetResponseSettings() {
        viewModel.settings.temperature = 0.7
        viewModel.settings.maxTokens = 2048
        viewModel.settings.reasoningLevel = .moderate
        viewModel.settings.useMaxTokens = false
        viewModel.settings.showReasoning = true
        viewModel.settings.showTokenSpeed = true
    }
}
