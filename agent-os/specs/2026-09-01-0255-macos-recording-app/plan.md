# Phase 2 — macOS recording app

## Context

The CLI (`cmd/transcribe`) covers everything *after* a recording exists: normalize with
ffmpeg, transcribe with whisper-cli, summarize with `claude --print`. It does not cover
making the recording, and that gap is why recordings arrive as 750 MB OBS screen captures
of a black window.

Recording is also the one part of this workflow a command line serves badly: it is live
and stateful. The user needs to see that capture is running and at what level, and needs
to start and stop it without typing — often while another app is in the foreground.

This spec builds a single macOS app covering the whole arc — start and stop a meeting
recording capturing microphone plus system audio, transcribe, summarize — with the
existing Go pipeline underneath, unchanged in substance.

### Decisions settled during shaping

- **Scope:** the full Phase 2 — GUI *and* recording, including system audio.
- **Shell:** a native SwiftUI app that owns the UI and the audio capture, and drives the
  existing `transcribe` binary as a subprocess. Rationale: Core Audio process taps are an
  Objective-C/Swift API, so Swift enters the project regardless. Wails would add Node,
  WebKit and cgo to a project whose stated identity is "standard library only", *and*
  still need the Swift helper — three worlds instead of two.
- **System audio:** Core Audio process taps (`AudioHardwareCreateProcessTap`, macOS 14.4+),
  not BlackHole. No virtual driver to install, and the roadmap already flags BlackHole as
  unreliable on macOS 26.
- **Form:** menu bar item for start/stop and live level, plus a window for the library.
- **Recording format:** Opus, 32 kbps, mono — measured on this project at 14 MB/hour with
  minutes equivalent to those from the uncompressed original.
- **Build:** SwiftPM plus a Makefile that assembles and ad-hoc signs the `.app`. No Xcode
  (not installed; only Command Line Tools, which ship the full SDK). Keeps the whole build
  as reviewable text and lets it be built and verified from the terminal.
- **Identity:** `Record Transcriber`, bundle ID `com.santiagomilos.record-transcriber`.
  Baked into the TCC grants, so it does not change after the first run.
- **Library:** a configurable folder, `~/Documents/Grabaciones` by default. One subfolder
  per session holding plain files.
- **Not sandboxed.** The app spawns `ffmpeg`, `whisper-cli` and `claude` from Homebrew and
  writes into `~/Documents`; the App Sandbox would break all three. This rules out Mac App
  Store distribution, which was never a goal.

### Cost

Nothing in this plan costs money. Every binary and model is free and local; summaries keep
using the existing Claude Code subscription exactly as the CLI does today. Ad-hoc signing
for personal use is free — the $99/year Apple Developer Program is only needed to
distribute a notarized app to other people, which is out of scope.

---

## Task 1: Save spec documentation

Create `agent-os/specs/2026-09-01-0255-macos-recording-app/` with:

- `plan.md` — this plan
- `shape.md` — scope, the decisions above and why each was taken
- `standards.md` — `agent-os/standards/index.yml` is empty, so this records that no
  project standards applied and that the code follows the conventions already in the repo
  (stdlib-only Go, subprocess boundaries, doc comments that say what the caller cannot see)
- `references.md` — the in-repo patterns this work reuses (below)
- `visuals/` — empty; no mockups were provided

`agent-os/specs/` does not exist yet and is created here.

**Reference implementations to record in `references.md`:**

- `internal/media/ffmpeg.go` — the subprocess idiom: `exec.CommandContext`, stderr captured
  into a buffer, error wrapped with the binary name and the captured message.
- `internal/asr/whispercli.go` — an external tool behind a Go interface, with its JSON
  output parsed by a pure function (`ParseWhisperJSON`) that is unit tested against
  `internal/asr/testdata/whisper-output.json`. The Swift NDJSON reader mirrors this shape.
- `cmd/transcribe/main.go:43` (`run`) — fail-fast ordering: every dependency check happens
  before any long work. The app keeps this ordering and surfaces it in the UI.
- `internal/modelstore/modelstore.go:83` (`download`) — write to `.part`, rename on success.
  The recorder uses the same discipline for in-progress captures.

---

## Task 2: Spike — system audio capture from an ad-hoc signed bundle

This is the one genuinely uncertain piece, so it gets proven before any UI is written.

Build a throwaway `app/spike/` executable that:

1. Creates a `CATapDescription` for a global tap excluding its own process, and calls
   `AudioHardwareCreateProcessTap`.
2. Creates an aggregate device (`kAudioHardwarePropertyPlugInCreateAggregateDevice`)
   containing the tap sub-device **and** the default input device, so Core Audio owns the
   clock sync between microphone and system audio rather than us fighting drift between
   two independent clocks.
3. Installs one `AudioDeviceIOProc`, sums all channels to mono, and writes 10 seconds of
   48 kHz Float32 to a raw file.

Package it as a minimal `.app` with `NSAudioCaptureUsageDescription` and
`NSMicrophoneUsageDescription`, ad-hoc sign it, run it from the Finder, and confirm macOS
issues the TCC prompt and the captured file contains audio from another app.

**Exit criteria:** a raw PCM file with both sources audible. If the tap turns out to
require a signing identity that ad-hoc cannot provide, stop here and report — the fallback
is `ScreenCaptureKit` audio-only capture, which works but asks for the heavier Screen
Recording permission. Everything downstream is unaffected either way.

---

## Task 3: Machine-readable progress in the Go CLI

The app needs structured progress, not prose on stderr. Two surgical changes:

**`internal/asr` — real transcription progress.** `whisper-cli` reports
`whisper_print_progress_callback: progress = NN%` when given `--print-progress`, which the
current invocation omits (`internal/asr/whispercli.go:56`). Add `--print-progress`, add a
`Progress func(percent int)` field to `WhisperCLI`, and wrap the writer passed to
`cmd.Stdout`/`cmd.Stderr` in a line scanner that extracts the percentage and forwards the
rest unchanged. Note that `Stderr` is typed `*os.File` today; widen it to `io.Writer` so
the wrapper fits. Keep the parsing in a small pure function so it is testable without
whisper-cli, the way `ParseWhisperJSON` is.

**`cmd/transcribe` — a `-json` flag.** When set, every human message that currently goes to
stderr is instead emitted as one NDJSON object per line on stdout:

```json
{"event":"input","name":"reunion.opus","duration_ms":963000}
{"event":"model","name":"large-v3-turbo","percent":42}
{"event":"stage","stage":"extract"}
{"event":"stage","stage":"transcribe"}
{"event":"progress","percent":37}
{"event":"transcript","language":"es","segments":167,"elapsed_ms":103000}
{"event":"output","kind":"txt","path":"/…/reunion.txt"}
{"event":"stage","stage":"summary"}
{"event":"output","kind":"summary","path":"/…/reunion.summary.md"}
{"event":"error","message":"whisper-cli is not on your PATH — …"}
```

Define the event structs in a new `internal/progress` package with an `Emitter` interface
and two implementations — `TextEmitter` (today's exact stderr output, the default) and
`JSONEmitter`. `run()` calls the emitter instead of `fmt.Fprintln(os.Stderr, …)`. This
keeps the CLI's current behaviour byte-for-byte when `-json` is absent.

**Tests:** the progress-line parser (valid line, malformed line, non-progress line) and the
JSON emitter (one event per line, exact literal JSON expected — no programmatic building).

---

## Task 4: Build system

New `app/Package.swift` (macOS 14.4 platform, no external dependencies) with an executable
target `RecordTranscriber` and a test target `RecordTranscriberTests`.

New top-level `Makefile`:

- `make transcribe` — `go build -o bin/transcribe ./cmd/transcribe`
- `make app` — `swift build -c release --package-path app`, then assemble
  `bin/Record Transcriber.app/` by hand: `Contents/MacOS/RecordTranscriber`,
  `Contents/Resources/transcribe` (the Go binary, embedded so the app has no PATH
  dependency on it), `Contents/Info.plist`, then `codesign --force --sign - --entitlements`
- `make run` — build and `open` the bundle
- `make test` — `go test ./...` and `swift test --package-path app`

`app/Resources/Info.plist` carries `CFBundleIdentifier`, `LSMinimumSystemVersion 14.4`,
`NSMicrophoneUsageDescription` and `NSAudioCaptureUsageDescription` (both user-facing
strings in Spanish, since they are shown to this user by macOS).

Extend `.gitignore` for `app/.build/` and `bin/*.app`.

---

## Task 5: Audio capture engine

`app/Sources/RecordTranscriber/Audio/`:

- `SystemAudioTap.swift` — the process tap and aggregate device from Task 2, promoted to a
  real type with proper teardown (`AudioHardwareDestroyProcessTap`, destroy aggregate) on
  stop and on error.
- `Recorder.swift` — the state machine: `idle → recording → stopping`. Owns the tap, the
  encoder and the elapsed timer, publishes `@Published` state for the UI.
- `OpusEncoder.swift` — spawns `ffmpeg -f f32le -ar 48000 -ac 1 -i pipe:0 -c:a libopus
  -b:a 32k -application voip <out>.opus.part` and writes IOProc buffers to its stdin.
  Renames `.part → .opus` on clean stop, mirroring `modelstore.download`, so an interrupted
  capture never leaves a file the pipeline would later choke on.
- `LevelMeter.swift` — peak/RMS per buffer, smoothed, for the menu bar meter.

**PATH:** a GUI app launched from the Finder inherits `/usr/bin:/bin:/usr/sbin:/sbin` and
will *not* find Homebrew. A `ToolPaths` helper probes `/opt/homebrew/bin` and
`/usr/local/bin`, and every `Process` the app spawns gets an augmented `PATH` in its
environment. Without this the app fails at runtime while the CLI works fine from a
terminal — the single most likely "works for me" bug in this task.

---

## Task 6: Library and settings

- `Library/Session.swift` — one recording: folder URL, start date, duration, and the files
  present (`audio.opus`, `transcript.txt`, `transcript.srt`, `summary.md`, `meta.json`).
- `Library/LibraryStore.swift` — creates `~/Documents/Grabaciones/YYYY-MM-DD HHmm/` per
  session, lists existing sessions by scanning the folder, and stays correct when the user
  moves or deletes a folder behind the app's back. The folder is the source of truth; no
  database.
- `Preferences/Settings.swift` — `@AppStorage`-backed: library folder, language
  (`auto`/`es`/`en`), output formats, summary kind (`none`/`resumen`/`minuta`), model.
  These map one-to-one onto the CLI flags in `cmd/transcribe/main.go:131`.

---

## Task 7: Menu bar

`MenuBarExtra` showing a record/stop control, a live level meter, and elapsed time. The
icon reflects state (idle / recording / processing) so capture is visible without opening
the window. Includes "Open library window" and "Preferences".

---

## Task 8: Main window

- Sidebar list of sessions, newest first, each with date, duration and status.
- Detail pane with tabs: transcript (timestamped segments) and summary (rendered markdown).
- Per-session actions: re-transcribe, generate/regenerate summary, reveal in Finder, delete.
- Drag and drop an existing audio or video file onto the window to run it through the same
  pipeline — this covers the "GUI over the existing CLI" case for recordings made elsewhere.
- A first-run state that reports missing dependencies (`ffmpeg`, `whisper-cli`, `claude`)
  with the `brew install` command to fix each, matching `checkDependencies`
  (`cmd/transcribe/main.go:210`) but as UI rather than a fatal error.

---

## Task 9: Pipeline integration

`Pipeline/TranscribeRunner.swift` spawns `Contents/Resources/transcribe` with `-json`, the
session's flags and the augmented PATH, and streams stdout line by line into `Codable`
event structs (`Pipeline/Event.swift`) that mirror Task 3's schema exactly.

On stop, the recorder hands the session folder to the runner; progress events drive a
determinate progress bar in the window and the menu bar icon; `output` events populate the
session. Cancelling terminates the process, which the Go side already handles through its
`signal.NotifyContext` (`cmd/transcribe/main.go:64`).

Model download on first run surfaces through the same `model` events, so the 1.6 GB fetch
shows real progress instead of an apparently hung app.

---

## Task 10: Tests, verification and docs

**Swift tests** (pure logic only — audio hardware is not unit tested):
NDJSON event decoding against a fixture of literal lines including a malformed one;
session folder naming; settings-to-flags mapping. Following the repo's testing conventions:
fixed dates, hardcoded expected values, no programmatic construction of expectations.

**Go tests:** those added in Task 3, plus `go test ./...` staying green.

**Docs:** update `agent-os/product/tech-stack.md` (Frontend is no longer N/A: SwiftUI,
SwiftPM, Core Audio; the app is a second artifact in the repo) and
`agent-os/product/roadmap.md` (mark Phase 2 shipped, record how the two open decisions were
resolved). Add an "App" section to `README.md` with `make app` and `make run`.

---

## Verification

```sh
make test                     # go test ./... and swift test
make app && make run
```

Then, end to end:

1. First launch — confirm macOS prompts for microphone and audio capture, and that denying
   either produces a legible message rather than silence.
2. Play a YouTube video, speak into the mic, record 60 seconds, stop.
3. Confirm `~/Documents/Grabaciones/<session>/audio.opus` exists, has no `.part` sibling,
   and is roughly 240 KB (the 32 kbps target — a wildly different size means the encoder
   is not getting the format it was promised).
4. Confirm both the video's audio and your voice are audible in it.
5. Confirm the transcript appears with a determinate progress bar during transcription,
   and that the summary is generated when the summary setting is not `none`.
6. `bin/transcribe reunion.opus` from a terminal still behaves exactly as before, and
   `bin/transcribe -json reunion.opus` emits one JSON object per line.
7. Quit and relaunch — the library window lists the session read back from disk.
