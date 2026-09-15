import CryptoKit
import Foundation

/// HighlightColor is one of the highlighter's inks. The raw values are what the
/// highlights file stores, so renaming a case orphans the marks made with it.
enum HighlightColor: String, Codable, CaseIterable {
    case yellow
    case green
    case pink
    case blue

    /// name is what the context menu calls the color.
    var name: String {
        switch self {
        case .yellow: return "Amarillo"
        case .green: return "Verde"
        case .pink: return "Rosa"
        case .blue: return "Azul"
        }
    }
}

/// SummaryHighlights is the set of marks the user made on one session's summary.
///
/// Offsets are UTF-16 offsets into the rendered summary, the string
/// `MarkdownText.attributedString` produces, because that is what the text view
/// reports as its selection; they are not offsets into the markdown. The marks
/// are kept sorted, never overlap, and adjacent marks of one color are merged,
/// so the file holds one entry per visible run.
struct SummaryHighlights: Codable, Equatable {
    struct Highlight: Codable, Equatable {
        var location: Int
        var length: Int
        var color: HighlightColor
        /// text is the rendered text under the mark. A mark whose range no longer
        /// holds it is dropped on load rather than drawn over the wrong words.
        var text: String

        var end: Int { location + length }
    }

    /// summarySHA256 identifies the summary the marks were made on. A summary
    /// written again by any path (the app, or the CLI run by hand) no longer
    /// matches, and its marks do not load.
    var summarySHA256: String
    var highlights: [Highlight] = []

    /// empty is a set with no marks for the given summary.
    static func empty(for summary: String) -> SummaryHighlights {
        SummaryHighlights(summarySHA256: digest(of: summary))
    }

    static func digest(of summary: String) -> String {
        SHA256.hash(data: Data(summary.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// load reads the marks for `summary` from `url`. A missing or malformed
    /// file, or one made on a different summary, is an empty set: marks nobody
    /// can place are not an error, they are marks on text that is gone.
    static func load(from url: URL, summary: String, rendered: String) -> SummaryHighlights {
        let empty = empty(for: summary)
        guard let data = try? Data(contentsOf: url),
              var loaded = try? JSONDecoder().decode(SummaryHighlights.self, from: data),
              loaded.summarySHA256 == empty.summarySHA256
        else { return empty }

        let text = rendered as NSString
        loaded.highlights = loaded.highlights.filter { highlight in
            highlight.location >= 0 && highlight.length > 0 && highlight.end <= text.length
                && text.substring(with: NSRange(location: highlight.location,
                                                length: highlight.length)) == highlight.text
        }
        return loaded
    }

    /// save writes the marks to `url`, or removes the file when there are none,
    /// so a session nobody marked carries no sidecar.
    func save(to url: URL) throws {
        guard !highlights.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// apply marks `range` of `rendered` in `color`, replacing whatever marks
    /// covered it. An empty or out-of-bounds range changes nothing.
    mutating func apply(_ color: HighlightColor, to range: NSRange, in rendered: String) {
        let text = rendered as NSString
        guard range.length > 0, range.location >= 0, NSMaxRange(range) <= text.length else { return }

        remove(in: range, rendered: rendered)
        highlights.append(Highlight(location: range.location,
                                    length: range.length,
                                    color: color,
                                    text: text.substring(with: range)))
        highlights.sort { $0.location < $1.location }
        mergeAdjacent(in: text)
    }

    /// remove clears every mark inside `range` of `rendered`, trimming or
    /// splitting the marks that only partly overlap it.
    mutating func remove(in range: NSRange, rendered: String) {
        let text = rendered as NSString
        guard range.length > 0 else { return }

        let start = range.location
        let end = NSMaxRange(range)
        highlights = highlights.flatMap { highlight -> [Highlight] in
            guard highlight.location < end, highlight.end > start else { return [highlight] }
            var pieces: [Highlight] = []
            if highlight.location < start {
                pieces.append(piece(of: highlight, from: highlight.location, to: start, in: text))
            }
            if highlight.end > end {
                pieces.append(piece(of: highlight, from: end, to: highlight.end, in: text))
            }
            return pieces
        }
    }

    /// touches reports whether any mark overlaps `range`.
    func touches(_ range: NSRange) -> Bool {
        highlights.contains { $0.location < NSMaxRange(range) && $0.end > range.location }
    }

    private func piece(of highlight: Highlight, from start: Int, to end: Int, in text: NSString) -> Highlight {
        let range = NSRange(location: start, length: end - start)
        return Highlight(location: start, length: range.length, color: highlight.color,
                         text: text.substring(with: range))
    }

    private mutating func mergeAdjacent(in text: NSString) {
        var merged: [Highlight] = []
        for highlight in highlights {
            guard let last = merged.last, last.end == highlight.location, last.color == highlight.color else {
                merged.append(highlight)
                continue
            }
            merged[merged.count - 1] = piece(of: last, from: last.location, to: highlight.end, in: text)
        }
        highlights = merged
    }
}
