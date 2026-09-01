import SwiftUI

/// MarkdownText renders the summary the way `claude --print` writes it:
/// headings, bullets and paragraphs.
///
/// SwiftUI's `Text(AttributedString)` applies inline emphasis but ignores the
/// block structure, so `## Acuerdos` would read as literal hashes. The blocks
/// are split here and only the inline markup inside each line is handed to
/// `AttributedString`.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ForEach(Array(Block.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.system(size: level == 1 ? 17 : (level == 2 ? 14 : 12.5), weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, level == 1 ? 0 : Theme.Space.sm)
        case let .bullet(marker, text):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                Text(marker)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textTertiary)
                Text(inline(text))
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, Theme.Space.sm)
        case let .paragraph(text):
            Text(inline(text))
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// inline parses one line's emphasis, links and code spans. Markdown the
    /// parser rejects is shown as written rather than dropped.
    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// Block is one rendered unit of the summary.
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case bullet(marker: String, text: String)
        case paragraph(String)

        /// parse splits markdown into blocks, joining consecutive plain lines
        /// into one paragraph the way markdown itself does.
        static func parse(_ markdown: String) -> [Block] {
            var blocks: [Block] = []
            var paragraph: [String] = []

            func flush() {
                guard !paragraph.isEmpty else { return }
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }

            for rawLine in markdown.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    flush()
                    continue
                }
                if let heading = heading(in: line) {
                    flush()
                    blocks.append(heading)
                    continue
                }
                if let bullet = bullet(in: line) {
                    flush()
                    blocks.append(bullet)
                    continue
                }
                paragraph.append(line)
            }
            flush()
            return blocks
        }

        private static func heading(in line: String) -> Block? {
            let hashes = line.prefix { $0 == "#" }.count
            guard hashes > 0, hashes <= 3 else { return nil }
            let rest = line.dropFirst(hashes)
            guard rest.hasPrefix(" ") else { return nil }
            return .heading(level: hashes, text: String(rest.dropFirst()))
        }

        private static func bullet(in line: String) -> Block? {
            for prefix in ["- ", "* "] where line.hasPrefix(prefix) {
                return .bullet(marker: "•", text: String(line.dropFirst(prefix.count)))
            }
            // An ordered item keeps its own number, since it is usually the
            // order that matters in a minute.
            let digits = line.prefix { $0.isNumber }
            if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
                let text = line.dropFirst(digits.count + 2)
                return .bullet(marker: "\(digits).", text: String(text))
            }
            return nil
        }
    }
}
