import SwiftUI

struct MessageBubbleView: View {
    @Environment(ChatViewModel.self) private var viewModel
    let message: Message
    let modelName: String
    let onQuote: (String) -> Void

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userMessage
            case .assistant:
                assistantMessage
            case .error:
                errorMessage
            }
        }
        .contextMenu {
            if message.role == .assistant {
                Button("Уточнить", systemImage: "quote.bubble") {
                    onQuote(selectedText() ?? message.content)
                }
                Menu("Feedback attachment", systemImage: "paperclip.badge.ellipsis") {
                    Button("Положительный", systemImage: "hand.thumbsup") {
                        viewModel.exportFeedback(for: message, positive: true)
                    }
                    Button("Отрицательный", systemImage: "hand.thumbsdown") {
                        viewModel.exportFeedback(for: message, positive: false)
                    }
                }
            }
            Button("Копировать", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            }
        }
        .padding(.vertical, 8)
    }

    private var userMessage: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 110)

            VStack(alignment: .trailing, spacing: 6) {
                if !message.attachments.isEmpty {
                    AttachmentChips(attachments: message.attachments)
                }
                Text(message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.tint)
                    .clipShape(.rect(cornerRadius: 16))
            }
        }
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
                if message.content.isEmpty {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Формирую ответ…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    RichMarkdownView(message.content)
                        .textSelection(.enabled)
                }

                if let metrics = message.metrics {
                    ResponseMetricsView(metrics: metrics)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var errorMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text("Запрос не выполнен")
                    .font(.callout.weight(.semibold))
                Text(message.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(.orange.opacity(0.08))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.orange.opacity(0.25), lineWidth: 1)
            }

            Spacer(minLength: 40)
        }
    }

    private func selectedText() -> String? {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        let range = textView.selectedRange()
        guard range.length > 0, range.location != NSNotFound,
              let swiftRange = Range(range, in: textView.string) else { return nil }
        return String(textView.string[swiftRange])
    }
}

private struct AttachmentChips: View {
    let attachments: [ChatAttachment]

    var body: some View {
        HStack {
            ForEach(attachments) { attachment in
                Label(
                    attachment.name,
                    systemImage: attachment.kind == .image ? "photo" : "doc"
                )
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .capsule)
            }
        }
    }
}

private struct ResponseMetricsView: View {
    @Environment(ChatViewModel.self) private var viewModel
    let metrics: GenerationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if viewModel.settings.showReasoning,
               let reasoning = metrics.reasoning,
               !reasoning.isEmpty {
                DisclosureGroup("Рассуждение · \(metrics.reasoningTokens) токенов") {
                    Text(reasoning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
                .font(.caption)
            }

            if viewModel.settings.showTokenSpeed {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                    Text("\(metrics.tokensPerSecond, format: .number.precision(.fractionLength(1))) TK/s")
                    Text("·")
                    Text("\(metrics.outputTokens) токенов")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct RichMarkdownView: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        let blocks = MarkdownDocumentParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index])
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            InlineMarkdownView(content)
                .font(headingFont(for: level))
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(let content):
            InlineMarkdownView(content)
                .font(.body)

        case .codeBlock(let language, let code):
            CodeBlockView(code: code, language: language)

        case .listItem(let indent, let content):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                InlineMarkdownView(content)
            }
            .font(.body)
            .padding(.leading, CGFloat(indent) * 16)

        case .numberedItem(let number, let content):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .monospacedDigit()
                InlineMarkdownView(content)
            }
            .font(.body)

        case .blockquote(let content):
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint.opacity(0.5))
                    .frame(width: 3)
                InlineMarkdownView(content)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 3)

        case .table(let rows):
            MarkdownTableView(rows: rows)

        case .divider:
            Divider()

        case .image(let alt, let url):
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url {
                    Text(url)
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.quinary, in: .rect(cornerRadius: 8))
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.bold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}

private struct InlineMarkdownView: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}

private struct MarkdownTableView: View {
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                GridRow {
                    ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
                        InlineMarkdownView(rows[rowIndex][columnIndex])
                            .font(rowIndex == 0 ? .callout.weight(.semibold) : .callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if rowIndex == 0 {
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .padding(10)
        .background(.quinary, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language, !language.isEmpty {
                HStack {
                    Text(language)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        Label("Копировать", systemImage: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
    }
}
