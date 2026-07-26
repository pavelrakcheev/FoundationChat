#if os(iOS)
import SwiftUI
import UIKit

struct MobileMessageView: View {
    @Environment(ChatViewModel.self) private var viewModel
    let message: Message
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
                    onQuote(message.content)
                }
            }
            Button("Копировать", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = message.content
            }
        }
        .padding(.vertical, 6)
    }

    private var userMessage: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 52)
            VStack(alignment: .trailing, spacing: 6) {
                if !message.attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(message.attachments) {
                                Label(
                                    $0.name,
                                    systemImage: $0.kind == .image ? "photo" : "doc"
                                )
                                .font(.caption)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                Text(message.content)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.tint, in: .rect(cornerRadius: 18))
            }
        }
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 9) {
            if message.content.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Формирую ответ…")
                        .foregroundStyle(.secondary)
                }
            } else {
                MobileMarkdownView(text: message.content)
                    .accessibilityIdentifier("mobile.assistant.content")
            }

            if let metrics = message.metrics, viewModel.settings.showTokenSpeed {
                Label(
                    "\(metrics.tokensPerSecond, format: .number.precision(.fractionLength(1))) TK/s · \(metrics.outputTokens) токенов",
                    systemImage: "gauge.with.dots.needle.33percent"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var errorMessage: some View {
        Label {
            Text(message.content)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.callout)
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 14))
    }
}

private struct MobileMarkdownView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownDocumentParser.parse(text)
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks.indices, id: \.self) { index in
                block(blocks[index])
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func block(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            inline(content)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 5 : 1)
        case .paragraph(let content):
            inline(content)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if let language {
                    Text(language)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(.quinary, in: .rect(cornerRadius: 12))
        case .listItem(let indent, let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                inline(content)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .numberedItem(let number, let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).").monospacedDigit()
                inline(content)
            }
        case .blockquote(let content):
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint.opacity(0.5))
                    .frame(width: 3)
                inline(content).foregroundStyle(.secondary)
            }
        case .table(let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(rows[row].indices, id: \.self) { column in
                                inline(rows[row][column])
                                    .font(row == 0 ? .callout.bold() : .callout)
                                    .frame(minWidth: 120, alignment: .leading)
                            }
                        }
                        if row == 0 { Divider() }
                    }
                }
                .padding(12)
            }
            .background(.quinary, in: .rect(cornerRadius: 12))
        case .divider:
            Divider()
        case .image(let alt, let url):
            Label(alt, systemImage: "photo")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let url {
                Text(url).font(.caption2).foregroundStyle(.tint)
            }
        }
    }

    private func inline(_ value: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(value)
    }
}
#endif
