import AppKit
import SwiftUI

struct ComposerView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let send: () -> Void

    private var canSend: Bool {
        viewModel.currentReadiness.canGenerate
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !viewModel.pendingAttachments.isEmpty)
            && !viewModel.isProcessing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            attachmentStrip

            HStack(alignment: .center, spacing: 10) {
                attachmentButton

                inputField

                if viewModel.isProcessing {
                    Button {
                        viewModel.cancelGeneration()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
                    .help("Остановить генерацию")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
                    .disabled(!canSend)
                    .help("Отправить")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.clear)
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !viewModel.pendingAttachments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(viewModel.pendingAttachments) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: attachment.kind == .image ? "photo" : "doc")
                            Text(attachment.name)
                                .lineLimit(1)
                            Button {
                                viewModel.removePendingAttachment(attachment.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Убрать вложение")
                        }
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var attachmentButton: some View {
        Button(action: chooseFiles) {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .disabled(viewModel.isProcessing)
        .help("Прикрепить изображение или документ")
    }

    private var inputField: some View {
        HStack(spacing: 0) {
            TextField(
                "Ask Apple AI",
                text: $text,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .focused(isFocused)
            .lineLimit(1...6)
            .onSubmit(send)
            .disabled(viewModel.isProcessing)
            .accessibilityLabel("Сообщение")

            modelPicker
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var modelPicker: some View {
        Menu {
            ForEach(ModelType.allCases) { type in
                Button {
                    viewModel.selectModel(type)
                } label: {
                    Label(
                        type.shortName,
                        systemImage: viewModel.modelType == type ? "checkmark" : type.iconName
                    )
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: viewModel.modelType.iconName)
                    .font(.caption)
                Text(viewModel.modelType.shortName)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.isProcessing)
        .help("Выбрать модель: Local или Cloud")
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Прикрепить"
        if panel.runModal() == .OK {
            viewModel.importAttachments(panel.urls)
        }
    }
}
