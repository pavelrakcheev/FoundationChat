import SwiftUI

struct SettingsView: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        TabView {
            GenerationSettingsTab()
                .tabItem {
                    Label("Генерация", systemImage: "slider.horizontal.3")
                }

            InstructionsSettingsTab()
                .tabItem {
                    Label("Инструкции", systemImage: "text.alignleft")
                }

            ModelsSettingsTab()
                .tabItem {
                    Label("Модели", systemImage: "cpu")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("О проекте", systemImage: "info.circle")
                }
        }
        .frame(width: 620, height: 480)
        .scenePadding()
        .task { await viewModel.checkAvailability() }
    }
}

private struct GenerationSettingsTab: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("Выборка") {
                LabeledContent {
                    Text(viewModel.settings.temperature, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                } label: {
                    Text("Temperature")
                }

                Slider(
                    value: $viewModel.settings.temperature,
                    in: 0...2,
                    step: 0.1
                ) {
                    Text("Temperature")
                } minimumValueLabel: {
                    Text("Точно")
                } maximumValueLabel: {
                    Text("Творчески")
                }

                Text(temperatureDescription(viewModel.settings.temperature))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Длина ответа") {
                Toggle(
                    "Ограничить число токенов",
                    isOn: $viewModel.settings.useMaxTokens
                )

                if viewModel.settings.useMaxTokens {
                    Stepper(
                        value: $viewModel.settings.maxTokens,
                        in: 64...32_768,
                        step: 64
                    ) {
                        LabeledContent(
                            "Максимум",
                            value: "\(viewModel.settings.maxTokens.formatted()) токенов"
                        )
                    }
                }
            }

            Section("Reasoning") {
                Picker(
                    "Глубина",
                    selection: $viewModel.settings.reasoningLevel
                ) {
                    ForEach(GenerationSettings.ReasoningLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.modelType.supportsReasoning)

                Text(reasoningDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var reasoningDescription: String {
        if viewModel.modelType.supportsReasoning {
            return "Параметр передаётся модели через ContextOptions.reasoningLevel."
        }
        return "Текущая системная on-device модель не предоставляет управляемый reasoning."
    }

    private func temperatureDescription(_ value: Double) -> String {
        switch value {
        case ..<0.3: "Детерминированные и консервативные ответы."
        case ..<0.8: "Сбалансированная выборка для обычного чата."
        case ..<1.3: "Более разнообразные и творческие ответы."
        default: "Экспериментальная выборка с повышенным риском ошибок."
        }
    }
}

private struct InstructionsSettingsTab: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Системные инструкции")
                    .font(.headline)
                Text(
                    "Изменение инвалидирует кэшированные сессии. При следующем запросе приложение создаст новый transcript с обновлёнными инструкциями и восстановит историю текущего чата."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $viewModel.settings.systemInstructions)
                .font(.body)
                .padding(6)
                .background(.background)
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.separator, lineWidth: 1)
                }

            HStack {
                Label(
                    "Markdown — формат вывода приложения, а не гарантированная возможность модели.",
                    systemImage: "text.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Вернуть стандартные") {
                    viewModel.resetInstructions()
                }
            }
        }
        .padding()
    }
}

private struct ModelsSettingsTab: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("Модели Apple") {
                ForEach(ModelType.allCases) { type in
                    ModelReadinessRow(
                        type: type,
                        readiness: viewModel.readiness[type] ?? .checking(for: type)
                    )
                }
            }

            Section {
                Button("Проверить доступность снова") {
                    Task { await viewModel.checkAvailability() }
                }
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
            Image(systemName: type.iconName)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(type.displayName)
                    .font(.body.weight(.medium))
                Text(readiness.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Контекст: \(readiness.contextLimit.formatted()) токенов")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            switch readiness.state {
            case .checking:
                ProgressView()
                    .controlSize(.small)
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
        .padding(.vertical, 3)
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 54, weight: .light))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Foundation Chat")
                    .font(.title.bold())
                Text("Apple Intelligence research playground")
                    .foregroundStyle(.secondary)
            }

            Text(
                "Проект создан совместно Павлом Ракчеевым, DeepSeek v4 Flash (Max Reasoning) в OpenCode Desktop и GPT‑5.6 Sol High в ChatGPT Codex."
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)

            Divider()
                .frame(maxWidth: 420)

            Text(
                "Приложение предназначено для исследования Foundation Models framework, Private Cloud Compute и локальных моделей в экосистеме Apple."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)

            Spacer()
        }
        .padding(.top, 28)
    }
}
