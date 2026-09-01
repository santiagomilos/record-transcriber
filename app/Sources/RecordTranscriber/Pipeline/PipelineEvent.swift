import Foundation

/// PipelineEvent is one line of `transcribe -json`.
///
/// Keep in sync with internal/progress/progress.go, which produces it. Unknown
/// event and stage names decode as `.unknown` rather than failing, so adding an
/// event on the Go side never breaks an app built before it.
struct PipelineEvent: Equatable {
    enum Kind: String, Decodable {
        case input, model, stage, progress, transcript, output, error, unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    enum Stage: String, Decodable {
        case extract, transcribe, summary, unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Stage(rawValue: raw) ?? .unknown
        }
    }

    var event: Kind = .unknown
    var stage: Stage?
    var name: String?
    var kind: String?
    var path: String?
    var language: String?
    var message: String?
    var segments = 0
    var percent = 0
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    var durationMS: Int64 = 0
    var elapsedMS: Int64 = 0
    var done = false

    /// fractionDownloaded is nil while the total size is unknown, which is what
    /// a determinate progress bar needs to know to stay indeterminate.
    var fractionDownloaded: Double? {
        guard bytesTotal > 0 else { return nil }
        return Double(bytesDone) / Double(bytesTotal)
    }

    /// decode reads one NDJSON line, returning nil for anything that is not a
    /// well-formed event. The stream can carry stray output from a tool, and a
    /// progress report is never worth failing a run over.
    static func decode(line: String) -> PipelineEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { return nil }
        return try? JSONDecoder().decode(PipelineEvent.self, from: Data(trimmed.utf8))
    }
}

extension PipelineEvent: Decodable {
    enum CodingKeys: String, CodingKey {
        case event, stage, name, kind, path, language, message, segments, percent, done
        case bytesDone = "bytes_done"
        case bytesTotal = "bytes_total"
        case durationMS = "duration_ms"
        case elapsedMS = "elapsed_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Every field but `event` is omitted when empty on the Go side, so each
        // one falls back to the zero value its absence means.
        event = try container.decode(Kind.self, forKey: .event)
        stage = try container.decodeIfPresent(Stage.self, forKey: .stage)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        segments = try container.decodeIfPresent(Int.self, forKey: .segments) ?? 0
        percent = try container.decodeIfPresent(Int.self, forKey: .percent) ?? 0
        bytesDone = try container.decodeIfPresent(Int64.self, forKey: .bytesDone) ?? 0
        bytesTotal = try container.decodeIfPresent(Int64.self, forKey: .bytesTotal) ?? 0
        durationMS = try container.decodeIfPresent(Int64.self, forKey: .durationMS) ?? 0
        elapsedMS = try container.decodeIfPresent(Int64.self, forKey: .elapsedMS) ?? 0
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}
