#if os(iOS)
import SwiftUI

struct MobileComposerView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let chooseFiles: () -> Void
    let send: () -> Void

    private var canSend: Bool {
        viewModel.currentReadiness.canGenerate
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !viewModel.pendingAttachments.isEmpty)
            && !viewModel.isProcessing
    }

    var body: some View {
        VStack(spacing: 8) {
            attachmentStrip

            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    Button(action: chooseFiles) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 46, height: 46)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(viewModel.isProcessing)
                    .accessibilityIdentifier("mobile.attachments")

                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Спросить Apple AI", text: $text, axis: .vertical)
                            .focused(isFocused)
                            .lineLimit(1...6)
                            .submitLabel(.send)
                            .onSubmit(send)
                            .disabled(viewModel.isProcessing)
                            .accessibilityIdentifier("mobile.composer")

                        Menu {
                            ForEach(ModelType.allCases) { type in
                                Button {
                                    viewModel.selectModel(type)
                                } label: {
                                    Label(
                                        type.fullName,
                                        systemImage: viewModel.modelType == type
                                            ? "checkmark"
                                            : type.iconName
                                    )
                                }
                            }
                        } label: {
                            Label(
                                viewModel.modelType.shortName,
                                systemImage: viewModel.modelType.iconName
                            )
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 30, height: 30)
                            .contentShape(.circle)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Модель: \(viewModel.modelType.shortName)")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .frame(minHeight: 46)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 23))

                    if viewModel.isProcessing {
                        Button {
                            viewModel.cancelGeneration()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 46, height: 46)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                        .accessibilityIdentifier("mobile.stop")
                    } else {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 46, height: 46)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            .regular
                                .tint(canSend ? .accentColor : nil)
                                .interactive(),
                            in: .circle
                        )
                        .disabled(!canSend)
                        .accessibilityIdentifier("mobile.send")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !viewModel.pendingAttachments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(viewModel.pendingAttachments) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: attachment.kind == .image ? "photo" : "doc")
                            Text(attachment.name).lineLimit(1)
                            Button {
                                viewModel.removePendingAttachment(attachment.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
#endif
