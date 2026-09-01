import Foundation
import Testing
@testable import RecordTranscriber

private func temporaryFolder() throws -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func writesAndReadsBackTheMetadataSidecar() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let metadata = SessionMetadata(durationSeconds: 963.5, language: "es", segments: 167)
    try metadata.save(to: folder)

    #expect(SessionMetadata.load(from: folder) == metadata)
}

@Test func writesTheSidecarAsMetaJSONInsideTheSessionFolder() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    try SessionMetadata(durationSeconds: 963.5, language: "es", segments: 167).save(to: folder)

    let written = try String(contentsOf: folder.appendingPathComponent("meta.json"), encoding: .utf8)
    #expect(written == """
    {
      "durationSeconds" : 963.5,
      "language" : "es",
      "segments" : 167
    }
    """)
}

@Test func omitsTheLanguageUntilTheSessionIsTranscribed() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    try SessionMetadata(durationSeconds: 20).save(to: folder)

    #expect(SessionMetadata.load(from: folder) == SessionMetadata(durationSeconds: 20,
                                                                 language: nil,
                                                                 segments: 0))
}

@Test func treatsAMissingSidecarAsNoMetadata() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(SessionMetadata.load(from: folder) == nil)
}

@Test func treatsAMalformedSidecarAsNoMetadata() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    try Data("{ not json".utf8).write(to: folder.appendingPathComponent("meta.json"))

    #expect(SessionMetadata.load(from: folder) == nil)
}

@Test func readsTheSidecarWhenTheSessionIsListed() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }

    let folder = root.appendingPathComponent("2026-09-01 0314")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try SessionMetadata(durationSeconds: 963.5, language: "es", segments: 167).save(to: folder)

    let store = LibraryStore(folder: root)

    #expect(store.sessions.first?.metadata?.durationSeconds == 963.5)
    #expect(store.sessions.first?.metadata?.language == "es")
    #expect(store.sessions.first?.metadata?.segments == 167)
}
