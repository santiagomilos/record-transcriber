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

    /// Status is what the list rows report, derived from the files present. There
    /// is nothing to keep in sync: a folder is in exactly one of these states by
    /// virtue of what it contains.
    enum Status: Equatable, Hashable {
        /// capturing is a part file with no finished audio beside it. The folder
        /// cannot say whether that capture is running right now or was
        /// interrupted; only the recorder knows, so the views that care ask it.
        case capturing
        /// empty is a folder a recording never wrote anything into.
        case empty
        case needsTranscription
        case ready
        case complete
    }

    let folder: URL
    let startedAt: Date
    /// metadata is the `meta.json` sidecar, read once when the session is listed.
    /// It is nil for sessions recorded before the sidecar existed.
    let metadata: SessionMetadata?

    var id: URL { folder }
    var name: String { folder.lastPathComponent }
    var audioURL: URL { folder.appendingPathComponent(Self.audioFileName) }
    var partialAudioURL: URL { folder.appendingPathComponent(Self.partialAudioFileName) }
    var summaryURL: URL { folder.appendingPathComponent("\(Self.transcriptBaseName).summary.md") }
    var transcriptBase: URL { folder.appendingPathComponent(Self.transcriptBaseName) }

    func transcriptURL(format: String) -> URL {
        folder.appendingPathComponent("\(Self.transcriptBaseName).\(format)")
    }

    var hasAudio: Bool { FileManager.default.fileExists(atPath: audioURL.path) }
    var hasSummary: Bool { FileManager.default.fileExists(atPath: summaryURL.path) }
    var hasTranscript: Bool {
        FileManager.default.fileExists(atPath: transcriptURL(format: "txt").path)
    }

    /// status reads the folder in the order the pipeline fills it, so the label
    /// is always the furthest point the session actually reached.
    var status: Status {
        if hasSummary { return .complete }
        if hasTranscript { return .ready }
        if hasAudio { return .needsTranscription }
        if FileManager.default.fileExists(atPath: partialAudioURL.path) { return .capturing }
        return .empty
    }

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
        metadata = SessionMetadata.load(from: folder)
    }

    /// displayName is what the user reads. The folder name is a sortable
    /// timestamp meant for the Finder, not something to put in a row.
    var displayName: String { SessionDateFormat.label(for: startedAt) }
}
