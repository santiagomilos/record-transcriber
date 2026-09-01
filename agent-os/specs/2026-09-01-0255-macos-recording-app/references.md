# References for the macOS Recording App

All references are in this repository. There is no similar app to borrow from; what gets
reused are the patterns the CLI already established for talking to external tools.

## Similar Implementations

### Driving an external binary

- **Location:** `internal/media/ffmpeg.go`
- **Relevance:** the app spawns `ffmpeg` directly to encode Opus while recording, and
  spawns `transcribe` after. Both follow this file's shape.
- **Key patterns:** `exec.CommandContext` so a cancelled context kills the child; stderr
  into a `bytes.Buffer`; the error wrapped with the binary name, the input path, and the
  captured stderr, so a failure reads as a sentence rather than "exit status 1".
  `Duration` also shows the deliberate choice to return a zero value rather than an error
  when the information is only used for display.

### An external tool behind an interface, with a pure parser

- **Location:** `internal/asr/whispercli.go`, tested by `internal/asr/whispercli_test.go`
  against `internal/asr/testdata/whisper-output.json`
- **Relevance:** the `-json` event stream added for the app is the same idea pointed the
  other way — the CLI now produces a machine-readable document, and Swift parses it.
- **Key patterns:** `ParseWhisperJSON` takes `[]byte` and returns a result, so the whole
  format is tested with no binary, no model and no network. The Swift-side event decoder is
  built and tested the same way, against a fixture of literal NDJSON lines. Also note the
  comment at line 35 explaining why an invalid flag combination is rejected locally: "the
  engine aborts rather than falling back", so the error is raised where it is legible.

### Fail-fast ordering

- **Location:** `cmd/transcribe/main.go:43` (`run`), `cmd/transcribe/main.go:210`
  (`checkDependencies`)
- **Relevance:** the app needs the same checks, but as UI rather than a fatal error — a
  first-run panel listing what is missing with the `brew install` line to fix it.
- **Key patterns:** every check that can fail without doing work happens before any long
  operation, so a missing dependency surfaces in a second rather than after a decode. Each
  dependency carries its own install command in the error message.

### Never leaving a partial file behind

- **Location:** `internal/modelstore/modelstore.go:83` (`download`)
- **Relevance:** the Opus encoder writes a live recording, and a crash or a forced quit
  mid-capture must not leave something the pipeline would later try to transcribe.
- **Key patterns:** write to `<path>.part`, rename on success, remove the part file on
  every error path. Also `progressWriter`, which throttles progress output to once a
  second — the same restraint applies to publishing audio levels to the UI.

### Output formatting

- **Location:** `internal/format/format.go`, tested by `internal/format/format_test.go`
- **Relevance:** the window renders transcript segments with timestamps; the formatting
  rules for a segment already live here and stay the single source for the files on disk.
- **Key patterns:** one small writer per format, each taking an `io.Writer` and a
  `*asr.Result`, so the caller owns the file handle.

## Environment Notes

Recorded during shaping, because they shaped the plan:

- macOS 26.6.2, Apple Silicon.
- Swift 6.3.3 with the full SDK, but **no Xcode** — only Command Line Tools at
  `/Library/Developer/CommandLineTools`. `xcodebuild` is unavailable; `swift build` works.
- `security find-identity -v -p codesigning` reports zero valid identities, so the bundle
  is ad-hoc signed (`codesign -s -`).
- Go 1.27.0.
