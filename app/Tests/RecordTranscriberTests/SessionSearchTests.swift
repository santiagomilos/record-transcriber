import Foundation
import Testing
@testable import RecordTranscriber

private func temporaryRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
}

/// makeSession writes a session folder with the given files and lists it.
private func makeSession(in root: URL, named name: String,
                         transcript: String? = nil, summary: String? = nil) throws -> Session {
    let folder = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if let transcript {
        try transcript.write(to: folder.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
    }
    if let summary {
        try summary.write(to: folder.appendingPathComponent("transcript.summary.md"), atomically: true, encoding: .utf8)
    }
    return Session(folder: folder)
}

@Test func findsASessionByItsTitle() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let budget = try makeSession(in: root, named: "Presupuesto anual", transcript: "hola")
    let other = try makeSession(in: root, named: "Retro", transcript: "hola")
    var index = SessionSearchIndex()

    let found = index.search("presupuesto", in: [budget, other])

    #expect(found.map(\.name) == ["Presupuesto anual"])
}

@Test func findsASessionByItsTranscript() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try makeSession(in: root, named: "A", transcript: "Hablamos del lanzamiento en octubre.")
    let second = try makeSession(in: root, named: "B", transcript: "Nada relevante.")
    var index = SessionSearchIndex()

    let found = index.search("lanzamiento", in: [first, second])

    #expect(found.map(\.name) == ["A"])
}

@Test func findsASessionByItsSummary() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try makeSession(in: root, named: "A", transcript: "x", summary: "## Decisiones\nContratar a un diseñador.")
    let second = try makeSession(in: root, named: "B", transcript: "x", summary: "## Decisiones\nNinguna.")
    var index = SessionSearchIndex()

    let found = index.search("diseñador", in: [first, second])

    #expect(found.map(\.name) == ["A"])
}

@Test func ignoresCaseAndAccents() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try makeSession(in: root, named: "A", transcript: "La REUNIÓN empezó tarde.")
    var index = SessionSearchIndex()

    #expect(index.search("reunion", in: [session]).map(\.name) == ["A"])
    #expect(index.search("Reunión", in: [session]).map(\.name) == ["A"])
    #expect(index.search("EMPEZO", in: [session]).map(\.name) == ["A"])
}

@Test func returnsNothingWhenNoSessionMatches() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try makeSession(in: root, named: "A", transcript: "Presupuesto.")
    var index = SessionSearchIndex()

    #expect(index.search("kubernetes", in: [session]).isEmpty)
}

@Test func anEmptyOrBlankQueryReturnsEverySessionInOrder() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try makeSession(in: root, named: "B", transcript: "uno")
    let second = try makeSession(in: root, named: "A", transcript: "dos")
    var index = SessionSearchIndex()

    #expect(index.search("", in: [first, second]).map(\.name) == ["B", "A"])
    #expect(index.search("  \n ", in: [first, second]).map(\.name) == ["B", "A"])
}

@Test func aSessionWithoutTranscriptOrSummaryMatchesOnlyByTitle() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try makeSession(in: root, named: "Entrevista")
    var index = SessionSearchIndex()

    #expect(index.search("entrevista", in: [session]).map(\.name) == ["Entrevista"])
    #expect(index.search("presupuesto", in: [session]).isEmpty)
}

@Test func theLibraryStoreSeesTextWrittenAfterAReload() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try makeSession(in: root, named: "A", transcript: "nada")
    let store = LibraryStore(folder: root)
    #expect(store.search("presupuesto").isEmpty)

    try "Revisamos el presupuesto.".write(
        to: session.transcriptURL(format: "txt"), atomically: true, encoding: .utf8)
    #expect(store.search("presupuesto").isEmpty)
    store.reload()

    #expect(store.search("presupuesto").map(\.name) == ["A"])
}
