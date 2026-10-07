import Foundation

/// SessionSearchIndex answers "which sessions mention this?" over a session's
/// title, transcript and summary.
///
/// Each session's text is read from disk the first time a query needs it and
/// kept, already folded for comparison, so typing does not reread the folder.
/// The index never notices the files changing: whoever owns it calls
/// `invalidate` when the library reloads.
struct SessionSearchIndex {
    private var folded: [URL: String] = [:]

    /// search returns the sessions whose title, transcript or summary contain
    /// the query, in the order given. Case and diacritics do not matter. A blank
    /// query matches everything.
    mutating func search(_ query: String, in sessions: [Session]) -> [Session] {
        let needle = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return sessions }
        return sessions.filter { text(of: $0).contains(needle) }
    }

    mutating func invalidate() {
        folded.removeAll()
    }

    /// fold lowercases and strips diacritics, so "Reunión" and "reunion" compare equal.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private mutating func text(of session: Session) -> String {
        if let cached = folded[session.id] { return cached }
        let parts = [session.name, session.displayName, session.transcriptText, session.summaryText]
        let text = Self.fold(parts.compactMap { $0 }.joined(separator: "\n"))
        folded[session.id] = text
        return text
    }
}
