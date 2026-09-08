import Testing
@testable import RecordTranscriber

/// The `transcript` event never carries the duration; it arrives on the `input`
/// event before decoding starts, exactly as `transcribe -json` writes it.
@Test @MainActor func carriesTheInputDurationIntoTheResult() {
    let runner = TranscribeRunner()
    let input = PipelineEvent.decode(line: #"{"event":"input","name":"PTT.opus","duration_ms":963000}"#)!
    let transcript = PipelineEvent.decode(line: #"{"event":"transcript","language":"es","segments":167,"elapsed_ms":103000}"#)!

    _ = runner.apply(input)
    _ = runner.apply(transcript)

    #expect(runner.result == TranscribeRunner.Result(language: "es",
                                                     segments: 167,
                                                     durationMS: 963000,
                                                     elapsedMS: 103000))
}

@Test @MainActor func reportsNoDurationWhenNoInputEventArrived() {
    let runner = TranscribeRunner()
    let transcript = PipelineEvent.decode(line: #"{"event":"transcript","language":"es","segments":167,"elapsed_ms":103000}"#)!

    _ = runner.apply(transcript)

    #expect(runner.result == TranscribeRunner.Result(language: "es",
                                                     segments: 167,
                                                     durationMS: 0,
                                                     elapsedMS: 103000))
}

@Test @MainActor func returnsTheMessageOfAnErrorEvent() {
    let runner = TranscribeRunner()
    let error = PipelineEvent.decode(line: #"{"event":"error","message":"cannot read input file"}"#)!

    #expect(runner.apply(error) == "cannot read input file")
}
