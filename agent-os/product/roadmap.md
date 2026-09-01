# Product Roadmap

## Phase 1: MVP — shipped

- Accept any audio or video file and normalize it to 16 kHz mono WAV with ffmpeg.
- Transcribe locally through whisper.cpp (`whisper-cli`) with the `large-v3-turbo` model.
- Automatic language detection, with an override flag for when detection guesses wrong.
- Download and cache the ggml models on first run, so setup is one command.
- Write the transcript as plain text, SRT, and VTT.
- Generate a summary or a structured meeting minute by piping the transcript into `claude --print`.

Verified end to end on a 16-minute Spanish recording: transcript plus minutes in 1m43s, language detected as `es`, 167 segments.

## Phase 2: Recording and a graphical app — shipped

`Record Transcriber.app` covers the whole arc: start and stop a meeting recording from the menu bar capturing microphone plus system audio, transcribe, summarize. The existing pipeline runs underneath unchanged — the app spawns the same `transcribe` binary the command line uses, embedded in its bundle.

Both open decisions were settled during the spec (`agent-os/specs/2026-09-01-0255-macos-recording-app/`).

**Shell: a native SwiftUI app driving the Go binary.** Core Audio process taps are an Objective-C and Swift API, so Swift entered the project whichever shell was chosen. Wails would have meant Go for the UI, Swift for the capture helper, and Node plus WebKit plus cgo added to a project whose stated identity is "standard library only" — three worlds where two suffice.

**System audio: Core Audio process taps, not BlackHole.** No virtual driver to install. The microphone and the tap go into one aggregate device so Core Audio owns the clock synchronization between them rather than the app reconciling two clocks that drift apart over a meeting.

Proven before the UI was written, on macOS 26.6.2 with an ad-hoc signed bundle: 15.0 s captured to the sample, system audio at −8.4 dB and microphone at −30.0 dB in the same stream. The one trap is that a bundled executable without an `NSApplication` is never issued the permission prompts at all — see `spike-result.md` in the spec folder.

**Recording format.** Measured on this project: Opus at 32 kbps mono costs 14 MB per hour against the 2.78 GB per hour of the OBS capture it replaces, and the meeting minutes generated from it are equivalent to those from the uncompressed original. Mono measured better than stereo at the same bitrate, and doubling the bitrate to 64 kbps changed the transcript by less than one point. The app records mono and spends no bits above 32 kbps.

The CLI gained a `-json` flag along the way, reporting a run as one JSON event per line so the app can show real progress. Without the flag its output is unchanged.

The UI was reworked afterwards (`agent-os/specs/2026-09-01-0419-menu-bar-panel-redesign/`). The menu bar panel had been three stock buttons; it is now a panel with a header, a record control that states what it captures, live recording and transcription state, and the five newest recordings with their length and status. Preferences became reachable for the first time, the app became a menu bar accessory with no Dock icon, and the panel and window moved onto one fixed dark palette rather than the system appearance.

That list needs a length per recording, which nothing measured before: the audio is Ogg/Opus, which AVFoundation cannot read, so the alternative was an `ffprobe` subprocess per row on every panel open. Each session now carries a `meta.json` written when the recording stops, holding the length plus the language and segment count that `transcribe -json` already reported and the app used to discard. Sessions recorded before it show no length; they are not backfilled.

Not done, and deliberately: notarized distribution to other machines. The app is ad-hoc signed for personal use, which costs nothing and needs no Apple Developer Program.

## Phase 2.5: The summary got a design — shipped

The pipeline declared record → transcribe → summarize, but the summarize step was never specified:
two hand-written prompts, each naming a fixed set of sections, applied to every recording alike.
`minuta` asked for topics, decisions and action items whether the recording was a requirements
call, a standup or a voice note.

`-summary auto` is the new default. It lists the facts the transcript supports before writing
anything — tagged as decisions, commitments, open questions, risks, underlying needs or context —
and the sections that appear are the ones those facts earned. `resumen` and `minuta` stay for
pinning a shape, and an install already carrying `minuta` is moved to `auto` once.

The shape is adaptive but there is no meeting-type classifier, which was the obvious design and
the rejected one (`agent-os/specs/2026-09-01-0524-adaptive-summaries/`). No production notetaker
documents classifying; the route with published evidence extracts labelled facts and derives the
outline from them, cutting hallucination and omission from 3 to 1 on a 5-point scale against
direct prompting. A classifier would have turned a continuous fact distribution into a brittle
discrete choice.

Three smaller things came out of the same reading. The transcript now reaches Claude timestamped
and *above* the instruction rather than below it, which is the documented ordering and was
backwards. Interpretation is quarantined: what was said and what the model concludes never share a
section. And a transcript is now a valid input, so a summary can be regenerated in seconds without
decoding the audio again — without which "the summary got better" stays an opinion.

Verified on the same 16-minute Spanish recording as Phase 1: `auto` surfaced the seven questions
the meeting left open and the fact that it ended without agreement, both of which the old `minuta`
had flattened into "Temas tratados".

## Phase 3: Later

- **Speaker diarization** — label who said what. The viable local path is `sherpa-onnx` running pyannote-segmentation-3.0 plus CAM++ as ONNX models, which needs no Python runtime.
- **Subtitle cue length** — whisper emits cues up to 30 seconds long, which read fine as a transcript but are unusable as subtitles. `whisper-cli --max-len` would split them.
- **Batch mode** — point the tool at a directory and transcribe everything in it.
- **In-process backend** — an optional cgo build using the whisper.cpp Go bindings, which would give live segment callbacks and real progress output during transcription.
- **Cloud backend** — an API-backed implementation behind the same `asr.Transcriber` interface, for machines that cannot run the model locally.
