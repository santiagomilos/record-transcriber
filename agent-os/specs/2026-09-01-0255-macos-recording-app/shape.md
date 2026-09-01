# macOS Recording App — Shaping Notes

## Scope

Phase 2 of the roadmap in full: a native macOS app that covers the whole arc from starting
a recording to reading its minutes. It captures microphone plus system audio, stops on a
click from the menu bar, and then runs the existing Go pipeline — ffmpeg, whisper-cli,
`claude --print` — over what it captured.

The CLI stays exactly as it is for terminal use. The app drives it as a subprocess, the
same way the CLI already drives ffmpeg and whisper-cli.

Out of scope: distribution to other people (notarization, Developer Program), the Mac App
Store, speaker diarization, and everything else listed under Phase 3.

## Decisions

**Shell — a native SwiftUI app driving the Go binary, not Wails.**
The roadmap left this open. Core Audio process taps are an Objective-C/Swift API, so Swift
enters the project no matter which shell is chosen. Wails would then mean Go for the UI,
Swift for the capture helper, and Node plus WebKit plus cgo added to a project whose stated
identity is "standard library only" — three worlds where two suffice. Choosing SwiftUI puts
the UI in the same language as the capture and leaves the Go side untouched as a backend.

**System audio — Core Audio process taps, not BlackHole.**
Also open in the roadmap. Process taps are native since macOS 14.4, need no virtual audio
driver installed, and avoid the reliability problems the roadmap already records for
BlackHole on macOS 26 Tahoe. The tap and the default input device go into a single
aggregate device, so Core Audio owns clock synchronization between the two sources rather
than the app compensating for drift between independent clocks.

**Form — menu bar plus window.**
Recording happens while another app is in the foreground, which is exactly when a window
is in the way. The menu bar item carries start/stop, the live input level, and elapsed
time; the window carries the library, transcripts and summaries, which need room to read.

**Recording format — Opus, 32 kbps, mono.**
Not a fresh decision: measured on this project at 14 MB/hour against 2.78 GB/hour for the
current OBS capture, with minutes equivalent to those from the uncompressed original. Mono
measured better than stereo at the same bitrate, and 64 kbps changed the transcript by less
than one point.

**Build — SwiftPM and a Makefile, not Xcode.**
Xcode is not installed on this machine; only Command Line Tools, which ship the full SDK
including SwiftUI. SwiftPM plus a Makefile that assembles and ad-hoc signs the bundle keeps
the entire build as reviewable text, with no binary `.xcodeproj` in git, and can be built
and verified from a terminal. The accepted cost is that rebuilding changes the ad-hoc
signature, so macOS may re-ask for the microphone and audio-capture permissions.

**Identity — `Record Transcriber`, `com.santiagomilos.record-transcriber`.**
TCC grants are keyed to the bundle identifier, so changing it later forces the user to
re-authorize. Settled before the first line of code.

**Library — a configurable folder, `~/Documents/Grabaciones` by default.**
One subfolder per session holding plain files: the Opus audio, the transcript, the summary.
The folder is the source of truth and there is no database, so a session can be moved,
copied or deleted from the Finder without the app losing track of anything.

**Not sandboxed.**
The app spawns `ffmpeg`, `whisper-cli` and `claude` from Homebrew and writes into
`~/Documents`. The App Sandbox would break all three. This rules out Mac App Store
distribution, which was never a goal.

**Structured progress over the subprocess boundary.**
The CLI reports progress as prose on stderr, which a GUI cannot use. Rather than have Swift
parse human sentences, the CLI gains a `-json` flag that emits one NDJSON event per line.
Without the flag its output stays byte-for-byte what it is today.

**The spike comes before the UI.**
Whether an ad-hoc signed bundle can create a process tap on macOS 26 is the one thing in
this plan that could fail outright. It is proven in a throwaway executable first, so a
failure costs a day rather than a week. The fallback, if it fails, is ScreenCaptureKit
audio-only capture, which works but asks the user for the heavier Screen Recording
permission.

## Cost

Nothing in this plan costs money. Every binary and model is free and runs locally;
summaries keep using the existing Claude Code subscription exactly as the CLI does today;
ad-hoc signing for personal use is free. The $99/year Apple Developer Program is only
needed to distribute a notarized app to other people, which is out of scope.

## Context

- **Visuals:** none provided. The interface follows native macOS conventions.
- **References:** the existing Go packages in this repo — see `references.md`.
- **Product alignment:** implements Phase 2 of `agent-os/product/roadmap.md` and resolves
  both decisions that document left open. The mission's core property — the audio never
  leaves the machine — is preserved: the app adds capture, and capture is local too.

## Standards Applied

`agent-os/standards/index.yml` is empty, so no project standards applied. See
`standards.md` for the conventions the code follows instead.
