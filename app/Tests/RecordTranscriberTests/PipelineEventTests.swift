import Testing
@testable import RecordTranscriber

/// The fixture is a literal copy of what `transcribe -json` writes, including a
/// blank line and a line of stray tool output, because both reach the reader in
/// practice.
private let eventStream = """
{"event":"input","name":"audio.opus","duration_ms":963000}
{"event":"stage","stage":"extract"}
{"event":"model","name":"large-v3-turbo","bytes_done":734003200,"bytes_total":1677721600}
{"event":"stage","stage":"transcribe"}
{"event":"progress","percent":37}
{"event":"transcript","language":"es","segments":167,"elapsed_ms":103000}
{"event":"output","kind":"txt","path":"/recordings/2026-09-01 0314/transcript.txt"}
{"event":"stage","stage":"summary","name":"minuta"}
{"event":"output","kind":"summary","path":"/recordings/2026-09-01 0314/transcript.summary.md"}
"""

@Test func decodesAnInputEvent() {
    let event = PipelineEvent.decode(line: #"{"event":"input","name":"audio.opus","duration_ms":963000}"#)
    #expect(event?.event == .input)
    #expect(event?.name == "audio.opus")
    #expect(event?.durationMS == 963000)
    #expect(event?.segments == 0)
    #expect(event?.done == false)
}

@Test func decodesTranscriptionProgress() {
    let event = PipelineEvent.decode(line: #"{"event":"progress","percent":37}"#)
    #expect(event?.event == .progress)
    #expect(event?.percent == 37)
}

@Test func readsAnOmittedPercentAsZero() {
    // The Go side omits a zero percent, and absence means zero rather than
    // "unknown", so a 0% report must not decode as anything else.
    let event = PipelineEvent.decode(line: #"{"event":"progress"}"#)
    #expect(event?.event == .progress)
    #expect(event?.percent == 0)
}

@Test func computesTheDownloadedFraction() {
    let event = PipelineEvent.decode(
        line: #"{"event":"model","name":"large-v3-turbo","bytes_done":838860800,"bytes_total":1677721600}"#)
    #expect(event?.fractionDownloaded == 0.5)
}

@Test func reportsNoFractionWhenTheTotalSizeIsUnknown() {
    let event = PipelineEvent.decode(
        line: #"{"event":"model","name":"silero-v5.1.2","bytes_done":5242880}"#)
    #expect(event?.fractionDownloaded == nil)
}

@Test func decodesAnErrorEvent() {
    let event = PipelineEvent.decode(
        line: #"{"event":"error","message":"cannot read input file"}"#)
    #expect(event?.event == .error)
    #expect(event?.message == "cannot read input file")
}

@Test func decodesAnUnknownEventInsteadOfFailing() {
    // An app built before a new Go event must skip it, not stop reading.
    let event = PipelineEvent.decode(line: #"{"event":"speakers","name":"two"}"#)
    #expect(event?.event == .unknown)
}

@Test func rejectsLinesThatAreNotEvents() {
    #expect(PipelineEvent.decode(line: "") == nil)
    #expect(PipelineEvent.decode(line: "   ") == nil)
    #expect(PipelineEvent.decode(line: "whisper_model_load: loading model") == nil)
    #expect(PipelineEvent.decode(line: "{not json}") == nil)
}

@Test func readsAWholeRun() {
    let events = eventStream.split(separator: "\n").compactMap { PipelineEvent.decode(line: String($0)) }
    #expect(events.count == 9)
    #expect(events.map(\.event) == [.input, .stage, .model, .stage, .progress, .transcript, .output, .stage, .output])
    #expect(events[5].language == "es")
    #expect(events[5].segments == 167)
    #expect(events[8].path == "/recordings/2026-09-01 0314/transcript.summary.md")
}
