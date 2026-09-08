import Foundation

/// Session is one recording and everything derived from it.
///
/// The folder on disk is the source of truth. There is no database, so a
/// session the user moves or deletes in the Finder simply stops being listed,
/// and one they copy back reappears.
///
/// A recording made by the app is `audio.opus`; a file imported from elsewhere
/// keeps its own name inside the folder. The audio is therefore resolved from
/// the folder's contents rather than assumed.
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
    /// audioURL is resolved once, when the session is listed: the detail view
    /// redraws on every hover, and listing the folder each time would cost a
    /// directory read per row per redraw.
    let audioURL: URL

    var id: URL { folder }
    var name: String { folder.lastPathComponent }
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

    /// summarizableTranscriptURL is the transcript a summary can be generated
    /// from: subtitles when they exist, because they keep the segment timings
    /// the summary prompt follows, otherwise plain text. Nil when neither is
    /// there.
    var summarizableTranscriptURL: URL? {
        for format in ["srt", "txt"] {
            let url = transcriptURL(format: format)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
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

    /// audioFile picks the recording among a folder's file names: `audio.opus`
    /// when the app recorded it, otherwise the first file the app did not derive
    /// from the audio. An empty folder resolves to `audio.opus` so a recording
    /// about to start has somewhere to write.
    ///
    /// Everything under the `transcript.` prefix is excluded rather than the
    /// three known outputs, because the pipeline also parks its intermediate
    /// `transcript.16k.wav` there while it runs.
    static func audioFile(among contents: [String]) -> String {
        if contents.contains(audioFileName) { return audioFileName }
        let candidates = contents.filter { name in
            name != SessionMetadata.fileName
                && !name.hasPrefix("\(transcriptBaseName).")
                && !name.hasSuffix(".part")
                && !name.hasPrefix(".")
        }
        return candidates.sorted().first ?? audioFileName
    }

    /// audioFile lists the folder and resolves its recording. A folder that
    /// cannot be listed resolves as an empty one.
    static func audioFile(in folder: URL) -> String {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return audioFile(among: contents)
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

    /// dateNamed parses the start time out of a folder named by
    /// `folderName(for:)`, with or without the ` N` suffix a collision adds.
    /// Nil for any other name.
    static func dateNamed(_ name: String) -> Date? {
        if let date = folderNameFormatter.date(from: name) { return date }
        guard let space = name.lastIndex(of: " "),
              Int(name[name.index(after: space)...]) != nil else { return nil }
        return folderNameFormatter.date(from: String(name[..<space]))
    }

    /// startDate reads the start time back out of a folder name, falling back to
    /// the folder's own creation date for anything named by hand.
    static func startDate(ofFolder folder: URL) -> Date {
        if let parsed = dateNamed(folder.lastPathComponent) {
            return parsed
        }
        let values = try? folder.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? .distantPast
    }

    init(folder: URL) {
        self.folder = folder
        startedAt = Session.startDate(ofFolder: folder)
        metadata = SessionMetadata.load(from: folder)
        audioURL = folder.appendingPathComponent(Session.audioFile(in: folder))
    }

    /// displayName is what the user reads. A folder named by its start time is
    /// a sortable timestamp meant for the Finder, so it is shown as a date
    /// label; any other name was chosen by the user or taken from their file,
    /// and is shown as it is.
    var displayName: String {
        Session.dateNamed(name) == nil ? name : SessionDateFormat.label(for: startedAt)
    }
}
