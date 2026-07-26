import Foundation

enum MarkdownBlock: Equatable {
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

enum MarkdownDocumentParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                blocks.append(parseCodeBlock(lines, index: &index))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                blocks.append(.blockquote(String(content)))
                index += 1
                continue
            }

            if let listItem = parseListItem(line, trimmed: trimmed) {
                blocks.append(listItem)
                index += 1
                continue
            }

            if let table = parseTable(lines, index: &index) {
                blocks.append(table)
                continue
            }

            if let image = parseImage(trimmed) {
                blocks.append(image)
                index += 1
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                guard !next.isEmpty, !startsBlock(next, following: lines, index: index) else {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func parseCodeBlock(
        _ lines: [String],
        index: inout Int
    ) -> MarkdownBlock {
        let opener = lines[index].trimmingCharacters(in: .whitespaces)
        let language = String(opener.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        index += 1

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                break
            }
            codeLines.append(lines[index])
            index += 1
        }

        return .codeBlock(
            language: language.isEmpty ? nil : language,
            code: codeLines.joined(separator: "\n")
        )
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let marker = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(marker.count) else { return nil }

        let content = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return .heading(level: marker.count, content: String(content))
    }

    private static func parseListItem(_ line: String, trimmed: String) -> MarkdownBlock? {
        for prefix in ["- ", "* ", "+ "] where trimmed.hasPrefix(prefix) {
            let content = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            let indentation = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
            return .listItem(indent: indentation, content: String(content))
        }

        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let suffix = trimmed.dropFirst(digits.count)
        guard suffix.hasPrefix(". ") else { return nil }
        let content = suffix.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return .numberedItem(number: Int(digits) ?? 1, content: String(content))
    }

    private static func parseTable(
        _ lines: [String],
        index: inout Int
    ) -> MarkdownBlock? {
        guard index + 1 < lines.count else { return nil }
        let header = tableCells(lines[index])
        let separator = tableCells(lines[index + 1])
        guard header.count >= 2,
              separator.count == header.count,
              separator.allSatisfy(isTableSeparator) else {
            return nil
        }

        var rows = [header]
        index += 2
        while index < lines.count {
            let cells = tableCells(lines[index])
            guard cells.count == header.count else { break }
            rows.append(cells)
            index += 1
        }
        return .table(rows)
    }

    private static func tableCells(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ cell: String) -> Bool {
        let marker = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return marker.count >= 3 && marker.allSatisfy { $0 == "-" }
    }

    private static func parseImage(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("!["),
              let altEnd = line.firstIndex(of: "]") else {
            return nil
        }
        let altStart = line.index(line.startIndex, offsetBy: 2)
        let alt = String(line[altStart..<altEnd])
        let suffix = line[line.index(after: altEnd)...]
        guard suffix.hasPrefix("("), let urlEnd = suffix.firstIndex(of: ")") else {
            return .image(alt: alt, url: nil)
        }
        let urlStart = suffix.index(after: suffix.startIndex)
        return .image(alt: alt, url: String(suffix[urlStart..<urlEnd]))
    }

    private static func startsBlock(
        _ line: String,
        following lines: [String],
        index: Int
    ) -> Bool {
        line.hasPrefix("```")
            || parseHeading(line) != nil
            || line == "---"
            || line == "***"
            || line == "___"
            || line.hasPrefix(">")
            || parseListItem(line, trimmed: line) != nil
            || parseImage(line) != nil
            || {
                var candidateIndex = index
                return parseTable(lines, index: &candidateIndex) != nil
            }()
    }
}
