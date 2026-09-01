# testdata

Recordings kept as fixtures for working on the pipeline, so a change can be judged against
material that has already been through it rather than against a fresh recording made for the
occasion.

**Nothing in here except this file is tracked.** The recordings and their transcripts carry real
conversations, and `.gitignore` excludes every extension they use (`*.mp4`, `*.txt`, `*.srt`,
`*.vtt`, `*.summary.md`). That is deliberate and should stay that way: this folder is a local
working set, not repository content. What is committed is this description of what the fixtures are
for.

Each fixture is one folder holding a `source` recording and the outputs the pipeline produced from
it. Transcripts use the same `transcript.*` base the app writes inside a session folder, so a
fixture can be fed to the CLI exactly as a real session would be.

## Working with a fixture

Summarizing an existing transcript skips ffmpeg and whisper, which turns a prompt change from a
two-minute decode into a few seconds:

```sh
make transcribe
./bin/transcribe -summary auto "testdata/reunion-planes-2026-08-31/transcript.srt"
```

That writes `transcript.summary.md` beside the input. Prefer the `.srt` over the `.txt`: it still
carries the segment timings, which the summary uses to follow the order of the conversation.

To exercise the whole pipeline instead, point the tool at the source recording.

## reunion-planes-2026-08-31

A 16-minute Spanish internal meeting about how a quoting flow should recommend a subscription
plan. It is the recording Phase 1 and Phase 2 of the roadmap were verified on, and it is a useful
fixture because of what it is rather than only what it says: it is a requirements discussion that
ends *without* agreement, it has recurring audio trouble, one participant's name is transcribed two
different ways, and several threads are left open.

That makes it the case where a fixed template and an adaptive one visibly diverge.
`minuta-before-redesign.summary.md` is the output of the fixed `minuta` prompt as it stood before
`agent-os/specs/2026-09-01-0524-adaptive-summaries/`, kept as the before-and-after reference: it
flattens the disagreement and the open questions into a single "Temas tratados" list.

| File | What it is |
|---|---|
| `source.mp4` | the original screen recording, 752 MB |
| `transcript.txt` | plain text, one segment per line, no timings |
| `transcript.srt` | subtitles with timings — the input to prefer |
| `transcript.vtt` | the same cues as WebVTT |
| `minuta-before-redesign.summary.md` | the old fixed `minuta`, kept for comparison |
