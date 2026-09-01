import Foundation

/// SessionMetadata is what a session folder cannot say by listing its files:
/// how long the recording is, what language it turned out to be, how many
/// segments the transcript has.
///
/// It is written as `meta.json` inside the session folder rather than kept in a
/// database, so a session stays self-contained: copy the folder and the metadata
/// travels with it. The recordings are Ogg/Opus, which AVFoundation cannot read,
/// so without this file the duration would cost an `ffprobe` subprocess per row
/// every time the panel opens.
struct SessionMetadata: Codable, Equatable, Hashable {
    static let fileName = "meta.json"

    /// durationSeconds is the recorded length, taken from the recorder's own
    /// clock. It stays zero for a session imported from a file, where nothing
    /// measured it.
    var durationSeconds: Double = 0
    /// language is what whisper detected, nil until the session is transcribed.
    var language: String?
    var segments: Int = 0

    /// load reads a session's sidecar. A missing or malformed file is nil rather
    /// than an error: metadata nobody wrote is not a broken session, it is a
    /// session recorded before this file existed.
    static func load(from folder: URL) -> SessionMetadata? {
        let url = folder.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionMetadata.self, from: data)
    }

    func save(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName))
    }
}
