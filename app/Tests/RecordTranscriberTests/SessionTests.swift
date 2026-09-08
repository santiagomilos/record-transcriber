import Foundation
import Testing
@testable import RecordTranscriber

/// A fixed instant, so the folder name a test asserts never depends on when it
/// runs: 2026-09-01 03:14:15 local time.
private let startedAt: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 9
    components.day = 1
    components.hour = 3
    components.minute = 14
    components.second = 15
    return Calendar.current.date(from: components)!
}()

@Test func namesASessionFolderByItsStartTime() {
    #expect(Session.folderName(for: startedAt) == "2026-09-01 0314")
}

@Test func readsTheStartTimeBackOutOfAFolderName() {
    let folder = URL(fileURLWithPath: "/recordings/2026-09-01 0314")
    let session = Session(folder: folder)
    #expect(Session.folderName(for: session.startedAt) == "2026-09-01 0314")
}

@Test func placesEveryFileOfASessionInsideItsFolder() {
    let session = Session(folder: URL(fileURLWithPath: "/recordings/2026-09-01 0314"))
    #expect(session.audioURL.path == "/recordings/2026-09-01 0314/audio.opus")
    #expect(session.transcriptURL(format: "txt").path == "/recordings/2026-09-01 0314/transcript.txt")
    #expect(session.transcriptURL(format: "srt").path == "/recordings/2026-09-01 0314/transcript.srt")
    #expect(session.summaryURL.path == "/recordings/2026-09-01 0314/transcript.summary.md")
    #expect(session.transcriptBase.path == "/recordings/2026-09-01 0314/transcript")
}

@Test func listsSessionsNewestFirstAndIgnoresLooseFiles() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    for name in ["2026-08-30 0900", "2026-09-01 0314", "2026-08-31 1830"] {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    try Data("loose".utf8).write(to: root.appendingPathComponent("notes.txt"))

    let store = LibraryStore(folder: root)

    #expect(store.sessions.map(\.name) == ["2026-09-01 0314", "2026-08-31 1830", "2026-08-30 0900"])
}

@Test func treatsAMissingLibraryFolderAsAnEmptyLibrary() {
    let missing = URL(fileURLWithPath: "/nonexistent/record-transcriber-library")
    let store = LibraryStore(folder: missing)
    #expect(store.sessions.isEmpty)
}

@Test func givesASecondRecordingInTheSameMinuteItsOwnFolder() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LibraryStore(folder: root)
    let first = try store.createSession(startedAt: startedAt)
    let second = try store.createSession(startedAt: startedAt)

    #expect(first.name == "2026-09-01 0314")
    #expect(second.name == "2026-09-01 0314 2")
}

@Test func deletesASessionFolderAndForgetsIt() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LibraryStore(folder: root)
    let session = try store.createSession(startedAt: startedAt)
    try store.delete(session)

    #expect(store.sessions.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: session.folder.path))
}

/// statusFolder writes a session folder containing exactly the named files, so
/// each status is asserted against the files that produce it.
private func statusFolder(containing files: [String]) throws -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
        .appendingPathComponent("2026-09-01 0314")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for file in files {
        try Data("x".utf8).write(to: folder.appendingPathComponent(file))
    }
    return folder
}

@Test func reportsACaptureInProgressWhileOnlyThePartFileExists() throws {
    let folder = try statusFolder(containing: ["audio.opus.part"])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(Session(folder: folder).status == .capturing)
}

@Test func reportsAFinishedRecordingAsNeedingTranscription() throws {
    let folder = try statusFolder(containing: ["audio.opus"])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(Session(folder: folder).status == .needsTranscription)
}

@Test func reportsATranscribedRecordingAsReady() throws {
    let folder = try statusFolder(containing: ["audio.opus", "transcript.txt"])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(Session(folder: folder).status == .ready)
}

@Test func reportsASummarisedRecordingAsComplete() throws {
    let folder = try statusFolder(containing: ["audio.opus", "transcript.txt", "transcript.summary.md"])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(Session(folder: folder).status == .complete)
}

@Test func reportsAFolderARecordingNeverWroteIntoAsEmpty() throws {
    let folder = try statusFolder(containing: [])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(Session(folder: folder).status == .empty)
}

// MARK: Audio resolution

@Test func resolvesTheRecorderFileWhenPresent() {
    #expect(Session.audioFile(among: ["PTT.opus", "audio.opus", "meta.json"]) == "audio.opus")
}

@Test func resolvesAnImportedFileByExcludingWhatTheAppDerived() {
    let contents = [
        "meta.json",
        "transcript.txt",
        "transcript.srt",
        "transcript.summary.md",
        "transcript.16k.wav",
        ".DS_Store",
        "PTT-20260901-WA0003.opus",
    ]
    #expect(Session.audioFile(among: contents) == "PTT-20260901-WA0003.opus")
}

@Test func ignoresAPartialCaptureAsAudio() {
    #expect(Session.audioFile(among: ["audio.opus.part"]) == "audio.opus")
}

@Test func fallsBackToTheRecorderNameForAnEmptyFolder() {
    #expect(Session.audioFile(among: []) == "audio.opus")
}

@Test func picksTheFirstFileByNameWhenSeveralQualify() {
    #expect(Session.audioFile(among: ["b.m4a", "a.mp3"]) == "a.mp3")
}

@Test func reportsAnImportedRecordingAsNeedingTranscription() throws {
    let folder = try statusFolder(containing: ["PTT-20260901-WA0003.opus", "meta.json"])
    defer { try? FileManager.default.removeItem(at: folder) }

    let session = Session(folder: folder)

    #expect(session.hasAudio)
    #expect(session.audioURL.lastPathComponent == "PTT-20260901-WA0003.opus")
    #expect(session.status == .needsTranscription)
}

@Test func prefersSubtitlesAsTheTranscriptToSummarize() throws {
    let folder = try statusFolder(containing: ["audio.opus", "transcript.txt", "transcript.srt"])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(Session(folder: folder).summarizableTranscriptURL?.lastPathComponent == "transcript.srt")
}

@Test func fallsBackToPlainTextWhenThereAreNoSubtitles() throws {
    let folder = try statusFolder(containing: ["audio.opus", "transcript.txt"])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(Session(folder: folder).summarizableTranscriptURL?.lastPathComponent == "transcript.txt")
}

@Test func hasNothingToSummarizeBeforeTranscription() throws {
    let folder = try statusFolder(containing: ["audio.opus"])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(Session(folder: folder).summarizableTranscriptURL == nil)
}

// MARK: Names

@Test func labelsADateNamedFolderByItsDate() {
    let session = Session(folder: URL(fileURLWithPath: "/recordings/2026-09-01 0314"))
    #expect(session.displayName == SessionDateFormat.label(for: startedAt))
}

@Test func labelsASuffixedDateFolderByItsDate() {
    let session = Session(folder: URL(fileURLWithPath: "/recordings/2026-09-01 0314 2"))
    #expect(Session.folderName(for: session.startedAt) == "2026-09-01 0314")
    #expect(session.displayName == SessionDateFormat.label(for: startedAt))
}

@Test func showsAnImportedFolderNameAsItIs() {
    let session = Session(folder: URL(fileURLWithPath: "/recordings/Archivos/PTT-20260901-WA0003"))
    #expect(session.displayName == "PTT-20260901-WA0003")
}

@Test func showsANameEndingInANumberAsItIs() {
    let session = Session(folder: URL(fileURLWithPath: "/recordings/Archivos/Reunión 2"))
    #expect(session.displayName == "Reunión 2")
}
