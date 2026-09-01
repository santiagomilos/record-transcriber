import Foundation

/// Session is one recording and everything derived from it.
///
/// The folder on disk is the source of truth. There is no database, so a
/// session the user moves or deletes in the Finder simply stops being listed,
/// and one they copy back reappears.
struct Session: Identifiable, Hashable {
    static let audioFileName = "audio.opus"
    /// transcriptBaseName is passed to `transcribe -o`, which appends its own
    /// extensions: transcript.txt, transcript.srt, transcript.summary.md.
    static let transcriptBaseName = "transcript"
    /// partialAudioFileName is what the encoder writes while recording. A
    /// capture that never finished keeps this name, so it is never mistaken for
    /// a recording ready to transcribe.
    static let partialAudioFileName = "audio.opus.part"

    let folder: URL
    let startedAt: Date

    var id: URL { folder }
    var name: String { folder.lastPathComponent }
    var audioURL: URL { folder.appendingPathComponent(Self.audioFileName) }
    var summaryURL: URL { folder.appendingPathComponent("\(Self.transcriptBaseName).summary.md") }
    var transcriptBase: URL { folder.appendingPathComponent(Self.transcriptBaseName) }

    func transcriptURL(format: String) -> URL {
        folder.appendingPathComponent("\(Self.transcriptBaseName).\(format)")
    }

    var hasAudio: Bool { FileManager.default.fileExists(atPath: audioURL.path) }
    var hasSummary: Bool { FileManager.default.fileExists(atPath: summaryURL.path) }

    /// transcriptText is the plain-text transcript, or nil when the session has
    /// not been transcribed yet.
    var transcriptText: String? {
        try? String(contentsOf: transcriptURL(format: "txt"), encoding: .utf8)
    }

    var summaryText: String? {
        try? String(contentsOf: summaryURL, encoding: .utf8)
    }

    /// folderNameFormatter names session folders so they sort chronologically
    /// as plain text in the Finder. The POSIX locale keeps the name identical
    /// whatever the user's region is set to.
    static let folderNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }()

    /// folderName is what a session started at date is called on disk.
    static func folderName(for date: Date) -> String {
        folderNameFormatter.string(from: date)
    }

    /// startDate reads the start time back out of a folder name, falling back to
    /// the folder's own creation date for anything the user renamed by hand.
    static func startDate(ofFolder folder: URL) -> Date {
        if let parsed = folderNameFormatter.date(from: folder.lastPathComponent) {
            return parsed
        }
        let values = try? folder.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? .distantPast
    }

    init(folder: URL) {
        self.folder = folder
        startedAt = Session.startDate(ofFolder: folder)
    }
}
