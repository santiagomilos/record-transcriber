import Foundation
import Testing
@testable import RecordTranscriber

private func temporaryRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
}

@Test func skipsTheImportsFolderWhenListingRecordings() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["2026-09-01 0314", "Archivos"] {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }

    let store = LibraryStore(folder: root, excludedFolderNames: ["Archivos"])

    #expect(store.sessions.map(\.name) == ["2026-09-01 0314"])
}

@Test func listsImportsInsideTheirOwnFolder() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imports = LibraryStore.importsFolder(in: root)
    try FileManager.default.createDirectory(
        at: imports.appendingPathComponent("PTT-20260901-WA0003"), withIntermediateDirectories: true)

    let store = LibraryStore(folder: imports)

    #expect(imports.lastPathComponent == "Archivos")
    #expect(store.sessions.map(\.name) == ["PTT-20260901-WA0003"])
}

@Test func createsANamedSessionAndSuffixesACollision() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LibraryStore(folder: root)
    let first = try store.createSession(named: "PTT")
    let second = try store.createSession(named: "PTT")

    #expect(first.name == "PTT")
    #expect(second.name == "PTT 2")
    #expect(store.sessions.map(\.name).sorted() == ["PTT", "PTT 2"])
}

@Test func createsTheImportsFolderOnFirstUse() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LibraryStore(folder: LibraryStore.importsFolder(in: root))
    try store.createSession(named: "PTT")

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
        atPath: root.appendingPathComponent("Archivos/PTT").path, isDirectory: &isDirectory)
    #expect(exists)
    #expect(isDirectory.boolValue)
}

@Test func renamesASessionFolderOnDisk() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(folder: root)
    let session = try store.createSession(named: "PTT")
    try Data("x".utf8).write(to: session.folder.appendingPathComponent("PTT.opus"))

    let renamed = try store.rename(session, to: "Reunión con Ana")

    #expect(renamed.name == "Reunión con Ana")
    #expect(renamed.folder.path == root.appendingPathComponent("Reunión con Ana").path)
    #expect(renamed.audioURL.lastPathComponent == "PTT.opus")
    #expect(!FileManager.default.fileExists(atPath: session.folder.path))
    #expect(FileManager.default.fileExists(atPath: renamed.audioURL.path))
    #expect(store.sessions.map(\.name) == ["Reunión con Ana"])
}

@Test func suffixesARenameThatCollides() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(folder: root)
    try store.createSession(named: "PTT")
    let other = try store.createSession(named: "Nota")

    let renamed = try store.rename(other, to: "PTT")

    #expect(renamed.name == "PTT 2")
}

@Test func trimsTheNewNameBeforeRenaming() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(folder: root)
    let session = try store.createSession(named: "PTT")

    let renamed = try store.rename(session, to: "  Nota  ")

    #expect(renamed.name == "Nota")
}

@Test func renamingToTheSameNameIsANoOp() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(folder: root)
    let session = try store.createSession(named: "PTT")

    let renamed = try store.rename(session, to: "PTT")

    #expect(renamed.folder == session.folder)
    #expect(store.sessions.map(\.name) == ["PTT"])
}

@Test func rejectsAnEmptyOrSlashedName() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(folder: root)
    let session = try store.createSession(named: "PTT")

    #expect(throws: LibraryError.self) { try store.rename(session, to: "") }
    #expect(throws: LibraryError.self) { try store.rename(session, to: "   ") }
    #expect(throws: LibraryError.self) { try store.rename(session, to: "a/b") }
    #expect(throws: LibraryError.self) { try store.rename(session, to: "a:b") }
    #expect(throws: LibraryError.self) { try store.rename(session, to: ".hidden") }
    #expect(store.sessions.map(\.name) == ["PTT"])
}

@Test func rejectsRenamingARecordingToTheImportsFolderName() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(folder: root, excludedFolderNames: ["Archivos"])
    let session = try store.createSession(named: "2026-09-01 0314")

    #expect(throws: LibraryError.self) { try store.rename(session, to: "Archivos") }
    #expect(store.sessions.map(\.name) == ["2026-09-01 0314"])
}
