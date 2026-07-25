import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let modelName: String

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

            VStack(alignment: .trailing, spacing: 5) {
                Text(message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.tint)
                    .clipShape(.rect(cornerRadius: 16))

                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.12))
                Image(systemName: "apple.intelligence")
                    .font(.body)
                    .foregroundStyle(.tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(modelName)
                        .font(.caption.weight(.semibold))
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
}

private struct RichMarkdownView: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { i in
                blockView(blocks[i])
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(.init(content))
                .font(.title3.weight(.semibold))
                .padding(.top, level == 1 ? 8 : 4)

        case .paragraph(let content):
            InlineMarkdownView(content)
                .font(.body)

        case .codeBlock(let lang, let code):
            CodeBlockView(code: code, language: lang)

        case .listItem(let indent, let content):
            HStack(alignment: .top, spacing: 4) {
                Text(String(repeating: "  ", count: indent) + "•")
                    .font(.body)
                InlineMarkdownView(content)
                    .font(.body)
            }

        case .numberedItem(let number, let content):
            HStack(alignment: .top, spacing: 4) {
                Text("\(number).")
                    .font(.body)
                InlineMarkdownView(content)
                    .font(.body)
            }

        case .blockquote(let content):
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint.opacity(0.5))
                    .frame(width: 3)
                InlineMarkdownView(content)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

        case .table(let rows):
            MarkdownTableView(rows: rows)

        case .divider:
            Divider()

        case .image(let alt, let url):
            VStack {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url { Text(url).font(.caption2).foregroundStyle(.tint) }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private enum Block {
        case heading(level: Int, content: String)
        case paragraph(String)
        case codeBlock(language: String?, code: String)
        case listItem(indent: Int, content: String)
        case numberedItem(number: Int, content: String)
        case blockquote(String)
        case table([[String]])
        case divider
        case image(alt: String, url: String?)
    }

    private func parseBlocks(_ md: String) -> [Block] {
        var blocks: [Block] = []
        let lines = md.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                let langOpt = lang.isEmpty ? nil : lang
                blocks.append(.codeBlock(language: langOpt, code: code.joined(separator: "\n")))
                i += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }

            if trimmed == "---" || trimmed == "***" {
                blocks.append(.divider); i += 1; continue
            }

            if trimmed.first == "#" {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if level <= 6 {
                    let content = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty {
                        blocks.append(.heading(level: level, content: String(content)))
                        i += 1; continue
                    }
                }
            }

            if trimmed.hasPrefix("> ") {
                let content = String(trimmed.dropFirst(2))
                blocks.append(.blockquote(content)); i += 1; continue
            }

            if let bullet = parseListPrefix(trimmed) {
                let content = String(trimmed.dropFirst(bullet.prefix.count)).trimmingCharacters(in: .whitespaces)
                if bullet.numbered {
                    blocks.append(.numberedItem(number: bullet.number, content: content))
                } else {
                    let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                    blocks.append(.listItem(indent: indent, content: content))
                }
                i += 1; continue
            }

            if let table = parseTable(lines, index: &i) {
                blocks.append(table); continue
            }

            if trimmed.hasPrefix("![") {
                let rest = String(trimmed.dropFirst(2))
                if let end = rest.firstIndex(of: "]") {
                    let alt = String(rest[..<end])
                    let after = rest[end...].dropFirst()
                    let url = after.hasPrefix("(") ? String(after.dropFirst().prefix(while: { $0 != ")" })) : nil
                    blocks.append(.image(alt: alt, url: url)); i += 1; continue
                }
            }

            blocks.append(.paragraph(line))
            i += 1
        }
        return blocks
    }

    private struct BulletPrefix {
        let prefix: String
        let numbered: Bool
        let number: Int
    }

    private func parseListPrefix(_ text: String) -> BulletPrefix? {
        let bullets: [(String, Bool)] = [("- ", false), ("* ", false), ("+ ", false)]
        for (b, _) in bullets {
            if text.hasPrefix(b) {
                return BulletPrefix(prefix: b, numbered: false, number: 0)
            }
        }
        let digits = text.prefix(while: { $0.isNumber })
        if digits.count >= 1, digits.count <= 3 {
            let rest = text.dropFirst(digits.count)
            if rest.hasPrefix(". ") {
                let num = Int(digits) ?? 1
                return BulletPrefix(prefix: String(digits + ". "), numbered: true, number: num)
            }
        }
        return nil
    }

    private func parseTable(_ lines: [String], index i: inout Int) -> Block? {
        let line = lines[i]
        let pipeCount = line.filter { $0 == "|" }.count
        guard pipeCount >= 3 else { return nil }

        let row = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        var rows: [[String]] = [row]
        i += 1

        if i < lines.count {
            let sep = lines[i].trimmingCharacters(in: .whitespaces)
            if sep.filter({ $0 == "-" }).count >= 2 || sep.hasPrefix("|---") {
                i += 1
            }
        }

        while i < lines.count {
            let rl = lines[i].trimmingCharacters(in: .whitespaces)
            if !rl.contains("|") || rl.hasPrefix("---") { break }
            rows.append(rl.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) })
            i += 1
        }

        return .table(rows)
    }
}

private struct MarkdownTableView: View {
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    ForEach(rows[i].indices, id: \.self) { j in
                        Text(rows[i][j])
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                }
                .background(i == 0 ? Color.gray.opacity(0.15) : Color.clear)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }
}

private struct InlineMarkdownView: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        if let attr = try? AttributedString(markdown: text) {
            Text(attr)
        } else {
            Text(text)
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
