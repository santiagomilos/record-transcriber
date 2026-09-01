# Standards for the macOS Recording App

`agent-os/standards/index.yml` contains no standards, so none were pulled in. What follows
are the conventions the existing code already holds itself to, which this work continues.

---

## Go

**Standard library only.** The module has no third-party dependencies and does not acquire
any here. Every capability the tool does not implement itself comes from a binary it shells
out to.

**Subprocess boundaries look the same everywhere.** `exec.CommandContext` so cancellation
propagates, stderr captured into a buffer, and errors wrapped with both the binary name and
the captured message — see `internal/media/ffmpeg.go` and `internal/asr/whispercli.go`.

**Fail fast.** Everything that can fail without doing work fails before the work starts.
`cmd/transcribe/main.go` checks dependencies, the input file, and the availability of the
`claude` binary before it downloads a model or decodes a second of audio.

**Parsing is a pure function.** `asr.ParseWhisperJSON` takes bytes and returns a result, so
it is tested against a fixture without whisper-cli, a model, or the network. New parsers
follow the same shape.

**Partial writes are never visible.** `modelstore.download` writes to a `.part` file and
renames on success, so an interruption never leaves something behind that would fail deep
inside another tool later.

**Comments say what the reader cannot see.** Doc comments describe what a call does for
someone who will never open the body; inline comments carry a constraint or a rejected
alternative, not narration.

---

## Swift

New to the repo, so the conventions are set here:

- **No third-party dependencies**, matching the Go side. SwiftUI, AVFoundation and Core
  Audio ship with the platform; `ffmpeg` and the `transcribe` binary are subprocesses.
- **The same subprocess discipline**: `Process` with an explicit executable URL and an
  augmented environment, stderr captured, errors carrying the tool name and its message.
- **Audio teardown is explicit.** A process tap and an aggregate device are system
  resources. Every path out of recording — stop, error, quit — destroys both.
- **UI state is derived, not duplicated.** The library folder on disk is the source of
  truth; views read from a store that scans it.

---

## Testing

- Boringly explicit: setup, execute, verify, in a straight line. Minimal logic inside a
  test.
- Deterministic data: fixed dates and identifiers, never `now()` or random values.
- Static expectations: the expected value is a literal, never built programmatically by the
  test.
- Beyond the happy path: malformed input, missing files, and the empty case.
- Test names describe the scenario.
- The language's standard tooling — `go test` and `swift test`. No frameworks added.

Audio hardware is not unit tested. The testable parts of this work are the NDJSON event
schema on both sides of the subprocess boundary, the whisper progress-line parser, session
folder naming, and the mapping from settings to CLI flags.

---

## Documentation

English, plain verbs, claims calibrated to evidence. The numbers in this spec — 14 MB/hour
for Opus, 2.78 GB/hour for the OBS capture, ~3% WER — come from measurements recorded in
`agent-os/product/roadmap.md` and `mission.md`, not from estimates.
