import Foundation
import Testing
@testable import RecordTranscriber

@Test func splitsPipeOutputIntoWholeLines() async {
    let pipe = Pipe()
    let lines = pipe.lines()

    pipe.fileHandleForWriting.write(Data("first\nsec".utf8))
    pipe.fileHandleForWriting.write(Data("ond\nthird\n".utf8))
    try? pipe.fileHandleForWriting.close()

    var collected: [String] = []
    for await line in lines { collected.append(line) }

    #expect(collected == ["first", "second", "third"])
}

@Test func yieldsAFinalLineThatHasNoTrailingNewline() async {
    let pipe = Pipe()
    let lines = pipe.lines()

    pipe.fileHandleForWriting.write(Data("error: failed to load model\nno newline here".utf8))
    try? pipe.fileHandleForWriting.close()

    var collected: [String] = []
    for await line in lines { collected.append(line) }

    #expect(collected == ["error: failed to load model", "no newline here"])
}

@Test func yieldsNothingForAPipeThatIsClosedUnused() async {
    let pipe = Pipe()
    let lines = pipe.lines()

    try? pipe.fileHandleForWriting.close()

    var collected: [String] = []
    for await line in lines { collected.append(line) }

    #expect(collected.isEmpty)
}

/// The regression this guards: a reader that stops draining leaves the writer
/// blocked in `write(2)` once the 64 KiB pipe buffer fills, which is what
/// stranded a transcription at 0% with whisper-cli asleep in `fflush`.
@Test func drainsFarMoreThanFitsInThePipeBuffer() async {
    let pipe = Pipe()
    let lines = pipe.lines()

    let writer = Task.detached {
        for index in 0..<20000 {
            pipe.fileHandleForWriting.write(Data("line \(index)\n".utf8))
        }
        try? pipe.fileHandleForWriting.close()
    }

    var count = 0
    var last = ""
    for await line in lines {
        count += 1
        last = line
    }
    await writer.value

    #expect(count == 20000)
    #expect(last == "line 19999")
}
