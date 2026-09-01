import Foundation
import Observation

/// AppModel is the one place the recorder, the library and the pipeline meet.
/// Views read it and call it; nothing else holds state.
@MainActor
@Observable
final class AppModel {
    let preferences: Preferences
    let library: LibraryStore
    let recorder = Recorder()
    let runner = TranscribeRunner()

    /// selection is the session shown in the detail pane.
    var selection: Session.ID?
    /// failure is the last thing that went wrong, shown as an alert.
    var failure: String?

    /// missingTools is read once at launch and after the user installs
    /// something, matching the CLI's habit of reporting a missing dependency
    /// before doing any work rather than after.
    private(set) var missingTools: [Tool] = Tool.missing

    /// activeSession is the recording in progress. It is remembered rather than
    /// looked up again after the capture ends, so stopping cannot silently fail
    /// to find the session it just wrote.
    @ObservationIgnored private var activeSession: Session?

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        library = LibraryStore(folder: preferences.libraryFolder)
    }

    var isBusy: Bool { recorder.state != .idle || runner.isRunning }

    func recheckTools() {
        missingTools = Tool.missing
    }

    func startRecording() async {
        guard recorder.state == .idle else { return }
        do {
            library.folder = preferences.libraryFolder
            let session = try library.createSession()
            activeSession = session
            selection = session.id
            try await recorder.start(writingTo: session.audioURL)
        } catch {
            activeSession = nil
            failure = error.localizedDescription
        }
    }

    /// stopRecording finishes the capture and immediately transcribes it, which
    /// is the whole point of the app: one gesture from "meeting over" to
    /// "minutes on disk".
    func stopRecording() async {
        guard recorder.isRecording, let session = activeSession else { return }
        activeSession = nil
        // The recorder's clock is the only measure of the length, and stopping
        // resets it, so it is read before the capture ends rather than after.
        let recorded = recorder.elapsed
        do {
            _ = try await recorder.stop()
            try? SessionMetadata(durationSeconds: recorded).save(to: session.folder)
            library.reload()
            await transcribe(session)
        } catch {
            failure = error.localizedDescription
        }
    }

    func cancelRecording() {
        activeSession = nil
        recorder.cancel()
        library.reload()
    }

    /// transcribe runs the pipeline over a session's audio.
    func transcribe(_ session: Session) async {
        guard session.hasAudio else {
            failure = "\(session.name) has no audio to transcribe."
            return
        }
        selection = session.id
        do {
            try await runner.run(input: session.audioURL,
                                 outputBase: session.transcriptBase,
                                 preferences: preferences)
            recordResult(in: session)
        } catch {
            failure = error.localizedDescription
        }
        library.reload()
    }

    /// recordResult folds what the pipeline learned about the audio into the
    /// session's sidecar, keeping whatever duration the recorder already wrote:
    /// its clock measured the capture, while the pipeline's duration is that of
    /// the file it decoded.
    private func recordResult(in session: Session) {
        guard let result = runner.result else { return }
        var metadata = SessionMetadata.load(from: session.folder) ?? SessionMetadata()
        metadata.language = result.language
        metadata.segments = result.segments
        if metadata.durationSeconds == 0 {
            metadata.durationSeconds = Double(result.durationMS) / 1000
        }
        try? metadata.save(to: session.folder)
    }

    /// importFile copies an existing recording into the library and transcribes
    /// it, so recordings made elsewhere go through the same pipeline.
    func importFile(_ url: URL) async {
        do {
            library.folder = preferences.libraryFolder
            let session = try library.createSession()
            let destination = session.folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            selection = session.id
            try await runner.run(input: destination,
                                 outputBase: session.transcriptBase,
                                 preferences: preferences)
            recordResult(in: session)
            library.reload()
        } catch {
            failure = error.localizedDescription
        }
    }

    func delete(_ session: Session) {
        do {
            try library.delete(session)
            if selection == session.id { selection = nil }
        } catch {
            failure = error.localizedDescription
        }
    }

    var selectedSession: Session? {
        guard let selection else { return nil }
        return library.sessions.first { $0.id == selection }
    }
}

/// formatDuration renders an elapsed time as mm:ss, or h:mm:ss past an hour.
func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
}
