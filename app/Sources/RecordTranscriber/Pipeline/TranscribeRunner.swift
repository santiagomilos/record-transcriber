import Foundation
import Observation

/// TranscribeRunner drives the `transcribe` binary and turns its NDJSON event
/// stream into something the UI can show.
///
/// The binary is the one shipped inside the app bundle, so the app and the
/// command line always run the same pipeline.
@MainActor
@Observable
final class TranscribeRunner {
    enum Phase: Equatable {
        case idle
        case downloadingModel(name: String, fraction: Double?)
        case extracting
        case transcribing(percent: Int)
        case summarizing(kind: String)

        /// label is what the UI shows next to the progress indicator.
        var label: String {
            switch self {
            case .idle: return ""
            case let .downloadingModel(name, _): return "Descargando modelo \(name)"
            case .extracting: return "Extrayendo audio"
            case .transcribing: return "Transcribiendo"
            case let .summarizing(kind): return "Generando \(Preferences.summaryKindProgressLabel(kind))"
            }
        }

        /// fraction is nil when the phase cannot report how far along it is,
        /// which is what tells a progress bar to stay indeterminate.
        var fraction: Double? {
            switch self {
            case let .downloadingModel(_, fraction): return fraction
            case let .transcribing(percent): return Double(percent) / 100
            default: return nil
            }
        }
    }

    /// Result is what the run found out about the recording itself, as opposed
    /// to the files it wrote.
    struct Result: Equatable {
        var language: String?
        var segments = 0
        var durationMS: Int64 = 0
        var elapsedMS: Int64 = 0
    }

    private(set) var phase: Phase = .idle
    private(set) var isRunning = false
    /// outputs maps a kind ("txt", "srt", "vtt", "summary") to the file written.
    private(set) var outputs: [String: URL] = [:]
    /// result is nil until the pipeline reports its transcript event, which is
    /// the only place the detected language and the segment count appear.
    private(set) var result: Result?

    @ObservationIgnored private var process: Process?
    /// inputDurationMS arrives on the `input` event, before any decoding, and
    /// is folded into `result` when the `transcript` event closes the run: the
    /// latter never carries the duration itself.
    @ObservationIgnored private var inputDurationMS: Int64 = 0

    /// run transcribes input, writing its outputs alongside outputBase, and
    /// returns when the binary exits. It throws when the run fails, carrying the
    /// message the pipeline reported rather than an exit status.
    ///
    /// summaryKind overrides the preferred one for this run only: `none` for an
    /// import that wants a transcript first, or the kind to generate from a
    /// transcript that already exists.
    func run(input: URL, outputBase: URL, preferences: Preferences,
             summaryKind: String? = nil) async throws {
        guard !isRunning else { return }
        guard let binary = TranscribeRunner.binary() else {
            throw RecordingError.missingTool("transcribe")
        }

        isRunning = true
        outputs = [:]
        result = nil
        inputDurationMS = 0
        phase = .extracting
        defer {
            isRunning = false
            phase = .idle
            process = nil
        }

        let events = Pipe()
        let diagnostics = Pipe()
        let process = Process()
        process.executableURL = binary
        process.environment = ToolPaths.childEnvironment
        process.arguments = preferences.transcribeArguments(input: input,
                                                            outputBase: outputBase,
                                                            summaryKind: summaryKind)
        process.standardOutput = events
        process.standardError = diagnostics
        self.process = process

        // Both streams are drained by their readability handlers from the moment
        // they are opened, so the child never blocks writing into a full pipe.
        // Only the diagnostics tail is worth keeping, which is all the buffering
        // policy lets through.
        let stderrTail = StderrTail()
        let diagnosticLines = diagnostics.lines(buffering: .bufferingNewest(StderrTail.limit))
        let eventLines = events.lines()
        let drained = Task.detached {
            for await line in diagnosticLines { await stderrTail.append(line) }
        }

        try process.run()

        var reportedError: String?
        for await line in eventLines {
            guard let event = PipelineEvent.decode(line: line) else { continue }
            if let message = apply(event) { reportedError = message }
        }

        process.waitUntilExit()

        if let reportedError {
            throw PipelineFailure(message: reportedError)
        }
        if process.terminationStatus != 0 {
            // The child is gone, so the diagnostics stream has reached end of
            // file; waiting for it is what makes its last lines part of the tail.
            await drained.value
            let tail = await stderrTail.text()
            throw PipelineFailure(message: tail.isEmpty
                ? "transcribe exited with status \(process.terminationStatus)."
                : tail)
        }
    }

    /// cancel asks the binary to stop. The Go side listens for SIGTERM and
    /// cleans up its intermediate WAV, so this leaves nothing behind.
    func cancel() {
        process?.terminate()
    }

    /// apply folds one event into the published state, returning the message of
    /// an error event. It is not private so a test can fold a literal stream
    /// without spawning the binary.
    func apply(_ event: PipelineEvent) -> String? {
        switch event.event {
        case .input:
            inputDurationMS = event.durationMS
        case .model:
            phase = .downloadingModel(name: event.name ?? "", fraction: event.fractionDownloaded)
        case .stage:
            switch event.stage {
            case .extract: phase = .extracting
            case .transcribe: phase = .transcribing(percent: 0)
            case .summary: phase = .summarizing(kind: event.name ?? "resumen")
            default: break
            }
        case .progress:
            phase = .transcribing(percent: event.percent)
        case .transcript:
            result = Result(language: event.language,
                            segments: event.segments,
                            durationMS: inputDurationMS,
                            elapsedMS: event.elapsedMS)
        case .output:
            if let kind = event.kind, let path = event.path {
                outputs[kind] = URL(fileURLWithPath: path)
            }
        case .error:
            return event.message
        default:
            break
        }
        return nil
    }

    /// binary prefers the copy inside the app bundle and falls back to one on
    /// PATH, which is what makes `swift run` usable during development.
    private static func binary() -> URL? {
        if let bundled = ToolPaths.transcribe { return bundled }
        return ToolPaths.locate("transcribe").map(URL.init(fileURLWithPath:))
    }
}

/// PipelineFailure carries the message the pipeline itself reported, which is
/// written for a person to read.
struct PipelineFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// StderrTail keeps the last few diagnostic lines, which is all that is useful
/// when a tool fails and all that should be shown in a dialog.
private actor StderrTail {
    /// limit is also what the diagnostics stream buffers, so a slow consumer
    /// drops exactly the lines this would have discarded anyway.
    static let limit = 12

    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
        if lines.count > Self.limit { lines.removeFirst(lines.count - Self.limit) }
    }

    func text() -> String {
        lines.joined(separator: "\n")
    }
}
