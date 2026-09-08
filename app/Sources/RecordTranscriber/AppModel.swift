import Foundation
import Observation
import UniformTypeIdentifiers

/// AppModel is the one place the recorder, the libraries and the pipeline meet.
/// Views read it and call it; nothing else holds state.
@MainActor
@Observable
final class AppModel {
    /// LibrarySection is which of the two lists the window shows.
    enum LibrarySection: Hashable, CaseIterable, Identifiable {
        case recordings
        case imports

        var id: Self { self }

        var title: String {
            switch self {
            case .recordings: return "Grabaciones"
            case .imports: return "Archivos"
            }
        }
    }

    /// ImportProgress is where the import queue stands: how many files are
    /// done and how many were queued in all.
    struct ImportProgress: Equatable {
        var done: Int
        var total: Int
    }

    let preferences: Preferences
    /// library holds the recordings the app made.
    let library: LibraryStore
    /// imports holds the files brought in from elsewhere, in a subfolder of the
    /// library so one folder is the whole library.
    let imports: LibraryStore
    let recorder = Recorder()
    let runner = TranscribeRunner()

    /// librarySection lives here rather than in the window so the panel can
    /// switch the window to the imports when it starts one.
    var librarySection: LibrarySection = .recordings
    /// selection is the session shown in the detail pane.
    var selection: Session.ID?
    /// failure is the last thing that went wrong, shown as an alert.
    var failure: String?
    /// importProgress is non-nil while the import queue is being drained,
    /// including the copy between two runs.
    private(set) var importProgress: ImportProgress?

    /// missingTools is read once at launch and after the user installs
    /// something, matching the CLI's habit of reporting a missing dependency
    /// before doing any work rather than after.
    private(set) var missingTools: [Tool] = Tool.missing

    /// activeSession is the recording in progress. It is remembered rather than
    /// looked up again after the capture ends, so stopping cannot silently fail
    /// to find the session it just wrote.
    @ObservationIgnored private var activeSession: Session?
    @ObservationIgnored private var pendingImports: [URL] = []
    /// cancellingImports tells the item being cancelled apart from one that
    /// failed, so cancelling never raises an alert.
    @ObservationIgnored private var cancellingImports = false

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        library = LibraryStore(folder: preferences.libraryFolder,
                               excludedFolderNames: [LibraryStore.importsFolderName])
        imports = LibraryStore(folder: LibraryStore.importsFolder(in: preferences.libraryFolder))
    }

    var isBusy: Bool { recorder.state != .idle || runner.isRunning || importProgress != nil }

    func recheckTools() {
        missingTools = Tool.missing
    }

    /// setLibraryFolder moves both libraries to a new root.
    func setLibraryFolder(_ url: URL) {
        preferences.libraryFolder = url
        syncFolders()
    }

    /// syncFolders points both stores at the preferred library folder. Only a
    /// change is assigned: assigning a store's folder reloads it.
    private func syncFolders() {
        if library.folder != preferences.libraryFolder {
            library.folder = preferences.libraryFolder
        }
        let importsFolder = LibraryStore.importsFolder(in: preferences.libraryFolder)
        if imports.folder != importsFolder {
            imports.folder = importsFolder
        }
    }

    /// store returns the library a session is listed in.
    private func store(owning session: Session) -> LibraryStore {
        session.folder.deletingLastPathComponent() == imports.folder ? imports : library
    }

    // MARK: Recording

    func startRecording() async {
        guard recorder.state == .idle else { return }
        do {
            syncFolders()
            let session = try library.createSession()
            activeSession = session
            librarySection = .recordings
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

    // MARK: Pipeline

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
        store(owning: session).reload()
    }

    /// summarize generates a session's summary from the transcript it already
    /// has, which skips the decode and takes seconds rather than minutes.
    func summarize(_ session: Session) async {
        guard let transcript = session.summarizableTranscriptURL else {
            failure = "\(session.name) no tiene transcripción que resumir."
            return
        }
        selection = session.id
        do {
            try await runner.run(input: transcript,
                                 outputBase: session.transcriptBase,
                                 preferences: preferences,
                                 summaryKind: preferences.onDemandSummaryKind)
        } catch {
            failure = error.localizedDescription
        }
        store(owning: session).reload()
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

    // MARK: Imports

    /// importFiles queues existing audio or video files to be copied into the
    /// imports library and transcribed one after another. Files queued while
    /// the queue is draining extend it.
    func importFiles(_ urls: [URL]) async {
        guard recorder.state == .idle else {
            failure = "Espera a que termine la grabación para transcribir archivos."
            return
        }
        let library = preferences.libraryFolder.standardizedFileURL.path + "/"
        var accepted: [URL] = []
        for url in urls {
            guard let type = UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .audio) || type.conforms(to: .movie) else {
                failure = "\(url.lastPathComponent) no es un archivo de audio o video."
                continue
            }
            // The app's own recordings are already here; importing one would
            // list it twice under the name "audio".
            guard !url.standardizedFileURL.path.hasPrefix(library) else {
                failure = "\(url.lastPathComponent) ya está en la biblioteca."
                continue
            }
            accepted.append(url)
        }
        guard !accepted.isEmpty else { return }

        pendingImports.append(contentsOf: accepted)
        librarySection = .imports
        if var progress = importProgress {
            progress.total += accepted.count
            importProgress = progress
            return
        }

        importProgress = ImportProgress(done: 0, total: accepted.count)
        while !pendingImports.isEmpty {
            let url = pendingImports.removeFirst()
            await importOne(url)
            importProgress?.done += 1
        }
        importProgress = nil
        cancellingImports = false
    }

    /// importOne copies a file into its own session folder and transcribes it,
    /// without a summary: a voice note wants its text first, and a summary is
    /// one click away once the transcript is there.
    private func importOne(_ url: URL) async {
        syncFolders()
        do {
            let name = preferences.importNaming.name(for: url, at: Date())
            let session = try imports.createSession(named: name)
            let destination = session.folder.appendingPathComponent(url.lastPathComponent)
            // Off the main actor: a clone on the same volume is instant, but a
            // copy from another disk is not, and the window has to keep drawing.
            try await Task.detached {
                try FileManager.default.copyItem(at: url, to: destination)
            }.value
            try? SessionMetadata(sourceName: url.lastPathComponent).save(to: session.folder)

            // Listed again so the audio resolves to the file just copied.
            let imported = Session(folder: session.folder)
            selection = imported.id
            try await runner.run(input: imported.audioURL,
                                 outputBase: imported.transcriptBase,
                                 preferences: preferences,
                                 summaryKind: "none")
            recordResult(in: imported)
        } catch {
            if !cancellingImports { failure = error.localizedDescription }
        }
        imports.reload()
    }

    /// cancelImports drops what is still queued and stops the run in progress.
    /// The CLI writes its outputs only after decoding, so the item being cancelled
    /// keeps its audio and nothing else.
    func cancelImports() {
        pendingImports.removeAll()
        cancellingImports = true
        runner.cancel()
    }

    // MARK: Library

    /// rename moves a session's folder to a new name. Refused while anything
    /// runs: the pipeline holds absolute paths into the folder.
    func rename(_ session: Session, to name: String) {
        guard !isBusy else { return }
        do {
            let renamed = try store(owning: session).rename(session, to: name)
            if selection == session.id { selection = renamed.id }
        } catch {
            failure = error.localizedDescription
        }
    }

    func delete(_ session: Session) {
        do {
            try store(owning: session).delete(session)
            if selection == session.id { selection = nil }
        } catch {
            failure = error.localizedDescription
        }
    }

    var selectedSession: Session? {
        guard let selection else { return nil }
        return library.sessions.first { $0.id == selection }
            ?? imports.sessions.first { $0.id == selection }
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
