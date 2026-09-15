import Foundation
import Testing
@testable import RecordTranscriber

/// The summary as `claude` wrote it, and its SHA-256
/// (`printf '# Acuerdos\n\n- Enviar la propuesta el lunes\n' | shasum -a 256`).
private let summary = "# Acuerdos\n\n- Enviar la propuesta el lunes\n"
private let summaryDigest = "4ff0daa7929851ab463e6bb0169de812fb708f086ed48e44741bf4edc6a43b75"

/// rendered stands in for what the text view shows. Offsets used below:
/// "Enviar" 9–15, " la " 15–19, "propuesta" 19–28, " el" 28–31.
private let rendered = "Acuerdos\nEnviar la propuesta el lunes"

private func temporaryFile() throws -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("record-transcriber-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("transcript.summary.highlights.json")
}

@Test func marksASelectionOnASummaryWithNoMarks() {
    var highlights = SummaryHighlights.empty(for: summary)

    highlights.apply(.yellow, to: NSRange(location: 9, length: 6), in: rendered)

    #expect(highlights == SummaryHighlights(summarySHA256: summaryDigest, highlights: [
        .init(location: 9, length: 6, color: .yellow, text: "Enviar"),
    ]))
}

@Test func overwritesThePartOfAMarkThatANewColorCovers() {
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.yellow, to: NSRange(location: 9, length: 22), in: rendered)

    highlights.apply(.green, to: NSRange(location: 19, length: 9), in: rendered)

    #expect(highlights.highlights == [
        .init(location: 9, length: 10, color: .yellow, text: "Enviar la "),
        .init(location: 19, length: 9, color: .green, text: "propuesta"),
        .init(location: 28, length: 3, color: .yellow, text: " el"),
    ])
}

@Test func mergesAdjacentMarksOfTheSameColor() {
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.pink, to: NSRange(location: 9, length: 6), in: rendered)

    highlights.apply(.pink, to: NSRange(location: 15, length: 4), in: rendered)

    #expect(highlights.highlights == [
        .init(location: 9, length: 10, color: .pink, text: "Enviar la "),
    ])
}

@Test func keepsAdjacentMarksOfDifferentColorsApart() {
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.pink, to: NSRange(location: 9, length: 6), in: rendered)

    highlights.apply(.blue, to: NSRange(location: 15, length: 4), in: rendered)

    #expect(highlights.highlights == [
        .init(location: 9, length: 6, color: .pink, text: "Enviar"),
        .init(location: 15, length: 4, color: .blue, text: " la "),
    ])
}

@Test func ignoresAnEmptyOrOutOfBoundsSelection() {
    var highlights = SummaryHighlights.empty(for: summary)

    highlights.apply(.yellow, to: NSRange(location: 9, length: 0), in: rendered)
    highlights.apply(.yellow, to: NSRange(location: 30, length: 50), in: rendered)

    #expect(highlights.highlights == [])
}

@Test func splitsAMarkWhenItsMiddleIsRemoved() {
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.yellow, to: NSRange(location: 9, length: 22), in: rendered)

    highlights.remove(in: NSRange(location: 19, length: 9), rendered: rendered)

    #expect(highlights.highlights == [
        .init(location: 9, length: 10, color: .yellow, text: "Enviar la "),
        .init(location: 28, length: 3, color: .yellow, text: " el"),
    ])
}

@Test func removingWhereNothingIsMarkedChangesNothing() {
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.green, to: NSRange(location: 9, length: 6), in: rendered)

    highlights.remove(in: NSRange(location: 19, length: 9), rendered: rendered)

    #expect(highlights.highlights == [
        .init(location: 9, length: 6, color: .green, text: "Enviar"),
    ])
}

@Test func reportsWhetherASelectionTouchesAMark() {
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.green, to: NSRange(location: 19, length: 9), in: rendered)

    #expect(highlights.touches(NSRange(location: 25, length: 5)))
    #expect(!highlights.touches(NSRange(location: 9, length: 10)))
}

@Test func writesTheMarksAsJSONAndReadsThemBack() throws {
    let url = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.green, to: NSRange(location: 19, length: 9), in: rendered)

    try highlights.save(to: url)

    let written = try String(contentsOf: url, encoding: .utf8)
    #expect(written == """
    {
      "highlights" : [
        {
          "color" : "green",
          "length" : 9,
          "location" : 19,
          "text" : "propuesta"
        }
      ],
      "summarySHA256" : "4ff0daa7929851ab463e6bb0169de812fb708f086ed48e44741bf4edc6a43b75"
    }
    """)
    #expect(SummaryHighlights.load(from: url, summary: summary, rendered: rendered) == highlights)
}

@Test func loadsNoMarksOnceTheSummaryWasWrittenAgain() throws {
    let url = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.green, to: NSRange(location: 19, length: 9), in: rendered)
    try highlights.save(to: url)

    let regenerated = "# Acuerdos\n\n- Enviar la propuesta el martes\n"
    let loaded = SummaryHighlights.load(from: url, summary: regenerated,
                                        rendered: "Acuerdos\nEnviar la propuesta el martes")

    #expect(loaded == SummaryHighlights(
        summarySHA256: "ca30a01b52cca7f1ae9fba96bd98b3b5744756139cafb6161ed118899fd4421c",
        highlights: []))
}

@Test func dropsAMarkWhoseTextIsNoLongerAtItsRangeAndKeepsTheRest() throws {
    let url = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try SummaryHighlights(summarySHA256: summaryDigest, highlights: [
        .init(location: 9, length: 6, color: .yellow, text: "Enviar"),
        .init(location: 19, length: 9, color: .green, text: "acuerdos!"),
        .init(location: 31, length: 50, color: .blue, text: " lunes"),
    ]).save(to: url)

    let loaded = SummaryHighlights.load(from: url, summary: summary, rendered: rendered)

    #expect(loaded.highlights == [
        .init(location: 9, length: 6, color: .yellow, text: "Enviar"),
    ])
}

@Test func treatsAMissingHighlightsFileAsNoMarks() throws {
    let url = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    #expect(SummaryHighlights.load(from: url, summary: summary, rendered: rendered)
        == SummaryHighlights(summarySHA256: summaryDigest, highlights: []))
}

@Test func treatsAMalformedHighlightsFileAsNoMarks() throws {
    let url = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Data("{ not json".utf8).write(to: url)

    #expect(SummaryHighlights.load(from: url, summary: summary, rendered: rendered)
        == SummaryHighlights(summarySHA256: summaryDigest, highlights: []))
}

@Test func removesTheFileWhenTheLastMarkIsCleared() throws {
    let url = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var highlights = SummaryHighlights.empty(for: summary)
    highlights.apply(.green, to: NSRange(location: 19, length: 9), in: rendered)
    try highlights.save(to: url)

    highlights.remove(in: NSRange(location: 19, length: 9), rendered: rendered)
    try highlights.save(to: url)

    #expect(!FileManager.default.fileExists(atPath: url.path))
}
