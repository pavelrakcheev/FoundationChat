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

            HStack(alignment: .bottom, spacing: 9) {
                attachmentButton
                messageField
                modelMenu
                sendButton
            }
        }
        .padding(10)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
                        .background(.quinary, in: .capsule)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var attachmentButton: some View {
        Button(action: chooseFiles) {
            Image(systemName: "plus")
                .frame(width: 17, height: 17)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(viewModel.isProcessing)
        .help("Прикрепить изображение или документ")
    }

    private var messageField: some View {
        TextField(
            "Сообщение для \(viewModel.modelType.shortName)",
            text: $text,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.body)
        .focused(isFocused)
        .lineLimit(1...6)
        .padding(.vertical, 7)
        .onSubmit(send)
        .disabled(viewModel.isProcessing)
        .accessibilityLabel("Сообщение")
    }

    private var modelMenu: some View {
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
            Label(viewModel.modelType.shortName, systemImage: viewModel.modelType.iconName)
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(viewModel.isProcessing)
        .help("Выбрать модель Apple: Local или Cloud")
    }

    @ViewBuilder
    private var sendButton: some View {
        if viewModel.isProcessing {
            Button {
                viewModel.cancelGeneration()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 17, height: 17)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help("Остановить генерацию")
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .frame(width: 17, height: 17)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(!canSend)
            .help("Отправить")
        }
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
