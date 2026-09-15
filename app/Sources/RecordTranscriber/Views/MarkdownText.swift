import SwiftUI

/// MarkdownText renders the summary the way `claude --print` writes it:
/// headings, bullets and paragraphs.
///
/// `AttributedString(markdown:)` applies inline emphasis but ignores the block
/// structure, so `## Acuerdos` would read as literal hashes. The blocks are
/// split here and only the inline markup inside each line is handed to
/// `AttributedString`.
enum MarkdownText {
    /// attributedString renders the summary as one string for a text view, with
    /// the body at `fontSize` and headings keeping their proportion to it.
    ///
    /// Blocks are separated by a single newline and a bullet renders as its
    /// marker, a tab and the item. Saved highlights are offsets into this
    /// string, so a change to what it contains drops the marks it moves.
    static func attributedString(markdown: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let primary = NSColor(Theme.textPrimary)
        let body = NSFont.systemFont(ofSize: fontSize)

        for (index, block) in Block.parse(markdown).enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = Theme.Space.sm

            switch block {
            case let .heading(level, text):
                let size = fontSize * (level == 1 ? 17 : (level == 2 ? 14 : 12.5)) / 12
                if level > 1, index > 0 { paragraph.paragraphSpacingBefore = Theme.Space.sm }
                result.append(inline(text, font: .systemFont(ofSize: size, weight: .semibold),
                                     color: primary, paragraph: paragraph))
            case let .bullet(marker, text):
                // The tab stop is where wrapped lines of the item start, so they
                // align under the text rather than under the marker.
                let indent = Theme.Space.sm + fontSize * 1.8
                paragraph.firstLineHeadIndent = Theme.Space.sm
                paragraph.headIndent = indent
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                result.append(NSAttributedString(string: "\(marker)\t", attributes: [
                    .font: body,
                    .foregroundColor: NSColor(Theme.textTertiary),
                    .paragraphStyle: paragraph,
                ]))
                result.append(inline(text, font: body, color: primary, paragraph: paragraph))
            case let .paragraph(text):
                result.append(inline(text, font: body, color: primary, paragraph: paragraph))
            }
        }
        return result
    }

    /// inline renders one line's emphasis, code spans and links in AppKit
    /// attributes. `NSAttributedString(AttributedString)` keeps the parsed
    /// presentation intents, but a text view draws them as plain text, so each
    /// run's font is chosen here. Markdown the parser rejects is shown as
    /// written rather than dropped.
    private static func inline(_ text: String, font: NSFont, color: NSColor,
                               paragraph: NSParagraphStyle) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var runFont = font
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    runFont = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                }
                if intent.contains(.stronglyEmphasized) {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask)
                }
                if intent.contains(.emphasized) {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: runFont,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: String(parsed[run.range].characters),
                                             attributes: attributes))
        }
        return result
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
