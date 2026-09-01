# Product Roadmap

## Phase 1: MVP — shipped

- Accept any audio or video file and normalize it to 16 kHz mono WAV with ffmpeg.
- Transcribe locally through whisper.cpp (`whisper-cli`) with the `large-v3-turbo` model.
- Automatic language detection, with an override flag for when detection guesses wrong.
- Download and cache the ggml models on first run, so setup is one command.
- Write the transcript as plain text, SRT, and VTT.
- Generate a summary or a structured meeting minute by piping the transcript into `claude --print`.

Verified end to end on a 16-minute Spanish recording: transcript plus minutes in 1m43s, language detected as `es`, 167 segments.

## Phase 2: Recording and a graphical app

The CLI covers everything after a recording exists. It does not cover making one, and that gap is why recordings arrive as 750 MB screen captures of a black window. Recording is also the one part of this workflow a command line serves badly: it is live and stateful, so the user needs to see that capture is running and at what level, and needs to start and stop it without typing.

The goal is a single macOS app covering the whole arc — start and stop a meeting recording capturing microphone plus system audio, transcribe, summarize — with the existing pipeline underneath.

Two decisions to settle before building; both are open.

**Shell: Go plus Wails, or a native SwiftUI app that drives the Go binary.** Wails reuses the current code in one codebase and one language, at the cost of a shallower fit with macOS conventions (menu bar, permissions, shortcuts). A native app fits macOS properly and reaches Core Audio directly, at the cost of splitting the project across two languages.

**System audio capture.** The current path depends on BlackHole, a virtual audio driver that is reported unreliable on macOS 26 Tahoe and is a legacy approach. The modern replacement is Core Audio process taps, native since macOS 14.4 and needing no virtual device, but the API is Objective-C and Swift. A helper binary written in Swift that captures through a process tap and writes raw PCM to stdout would keep the subprocess architecture intact and avoid cgo entirely, the same way ffmpeg and whisper-cli are already driven.

**Recording format.** Measured on this project: Opus at 32 kbps mono costs 14 MB per hour against the 2.78 GB per hour of the current OBS capture, and the meeting minutes generated from it are equivalent to those from the uncompressed original. Mono measured better than stereo at the same bitrate, and doubling the bitrate to 64 kbps changed the transcript by less than one point. Record mono, and do not spend bits above 32 kbps.

## Phase 3: Later

- **Speaker diarization** — label who said what. The viable local path is `sherpa-onnx` running pyannote-segmentation-3.0 plus CAM++ as ONNX models, which needs no Python runtime.
- **Subtitle cue length** — whisper emits cues up to 30 seconds long, which read fine as a transcript but are unusable as subtitles. `whisper-cli --max-len` would split them.
- **Batch mode** — point the tool at a directory and transcribe everything in it.
- **In-process backend** — an optional cgo build using the whisper.cpp Go bindings, which would give live segment callbacks and real progress output during transcription.
- **Cloud backend** — an API-backed implementation behind the same `asr.Transcriber` interface, for machines that cannot run the model locally.
