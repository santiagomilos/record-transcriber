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
