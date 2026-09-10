# record-transcriber

Records a meeting, turns it into text, and summarizes it — locally. The audio
never leaves the machine and there is no per-hour cost.

There are two ways in: a macOS app that records and then runs the pipeline, and
the command-line tool it drives, for recordings that already exist.

## Install

On a Mac with Apple Silicon and macOS 14.4 or later, open Terminal and run:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/santiagomilos/record-transcriber/main/install.sh)"
```

The script installs Homebrew if it is missing (it asks for your password),
then `ffmpeg` and `whisper-cpp`, downloads the latest release from this
repository's Releases page, puts `Record Transcriber.app` in `/Applications`
and opens it. Running it again updates the app in place. It edits no shell
profile and signs in to nothing.

Summaries need [Claude Code](https://code.claude.com/docs/en/setup) installed
and signed in, which the script checks but does not install: it prints the
install command (`curl -fsSL https://claude.ai/install.sh | bash`) and asks you
to run `claude` once to sign in. Claude Code 2.1 or newer is required, tested
against 2.1.267; `claude --help` must list `--restricted`. Without it the app
records and transcribes, and the summary button stays disabled.

Models are downloaded on the first transcription into
`~/Library/Caches/record-transcriber/models/` on macOS (`~/.cache/...` on
Linux): the transcription model, `large-v3-turbo` at 1.6 GB, plus a small
Silero voice-activity model used to skip silence. The first transcription
therefore takes minutes longer than the rest.

To install by hand instead, download `Record-Transcriber-arm64.zip` from the
latest release, unzip it and drag the app into Applications. The app is
signed ad-hoc and not notarized, so a copy downloaded with a browser carries
the quarantine flag and macOS refuses to open it the first time. On macOS 15
and later, open System Settings > Privacy & Security (Ajustes del Sistema >
Privacidad y seguridad), scroll to the notice that Record Transcriber was
blocked, click Open Anyway (Abrir igualmente) and confirm; Control-click >
Open no longer suffices since Sequoia. On macOS 14, Control-click the app and
choose Open once. Or remove the flag in a terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Record Transcriber.app"
```

The install script does this for you, which is why the one-liner never hits
the prompt.

macOS keys the microphone and system-audio permissions to the app's signature,
and an ad-hoc signature changes with every build, so each new version asks
again on the first recording. If the prompt never reappears and a recording
captures nothing, remove Record Transcriber under System Settings > Privacy &
Security > Microphone and record again, or reset the grant:

```sh
tccutil reset Microphone com.santiagomilos.record-transcriber
```

## Build from source

```sh
brew install ffmpeg whisper-cpp
make            # builds bin/transcribe and "bin/Record Transcriber.app"
```

Needs Go 1.27 and a Swift 6 toolchain (the Command Line Tools are enough; no
Xcode project exists). A build made this way reports version `0.0.0`: the
version lives in the git tag and is stamped into the bundle by `make dist`,
see Release below.

## The app

```sh
make run
```

The app lives only in the menu bar — no Dock icon. Its panel starts and stops the
recording, shows a level meter for the microphone and for the system audio
separately (the usual failure is capturing only your own voice, and one mixed bar
hides it), reports the transcription phases as they run, lists the five newest
recordings, and opens preferences. Stopping transcribes the recording and
generates its minutes without another click. While a recording runs, the menu bar
icon shows the elapsed time.

Recordings land in `~/Documents/Grabaciones/<date time>/` as plain files
(`audio.opus`, `transcript.txt`, `transcript.srt`, `transcript.summary.md`, and a
small `meta.json`), one folder per session, changeable in preferences. The folder
is the only state the app keeps, so a session can be moved, copied or deleted
from the Finder.

`meta.json` holds what the files cannot say: the recorded length, the detected
language and the segment count. It exists because the audio is Ogg/Opus, which
AVFoundation cannot read, so the alternative was an `ffprobe` subprocess per row
every time the panel opens. Sessions recorded before it show no length.

The window lists those sessions with their date, length and status, and shows
what each produced — the transcript as text, the summary rendered as Markdown.

Audio that was not recorded here — a WhatsApp voice note, an `.m4a`, a video —
goes through the same pipeline from the window's second list, "Archivos". Pick
files with the "Transcribir archivo…" button (in the window or in the menu bar
panel) or drag them onto the window; several at once are transcribed one after
another, and the queue can be cancelled. Each file is copied into
`~/Documents/Grabaciones/Archivos/<name>/` so the folder stays self-contained,
and is named after the file (or after the import time, a preference); any item
can be renamed later, which renames its folder. An imported file gets a
transcript only. "Resumir" in the detail view generates the summary on demand by
running the CLI over the transcript, which takes seconds rather than a decode.

The panel and the window use a fixed dark palette instead of following the system
appearance, which is deliberate: the app looks the same everywhere, at the cost of
a theme maintained by hand in `app/Sources/RecordTranscriber/Views/Theme.swift`.

System audio is captured with a Core Audio process tap, native since macOS 14.4,
so there is no virtual audio driver to install. Audio is written as Opus at
32 kbps mono: 14 MB per hour, measured to produce minutes equivalent to the
uncompressed original.

macOS asks for microphone access on the first recording. The app is signed
ad-hoc because this project has no signing identity, and the signature changes
whenever it is rebuilt, so `make app` may make macOS ask again; see Install
above for what to do when it stops asking.

## Use the CLI

```sh
# transcript as .txt and .srt next to the input file
transcribe reunion.mp4

# subtitles only, forcing Spanish instead of detecting it
transcribe -f srt,vtt -l es reunion.mp4

# transcript plus a summary whose sections follow what the recording turned out to be
transcribe -summary auto reunion.mp4

# summarize a transcript that already exists, skipping the decode
transcribe -summary auto reunion.srt
```

| Flag | Default | Meaning |
|---|---|---|
| `-o`, `-output` | input path without its extension | base path for output files |
| `-f`, `-format` | `txt,srt` | any of `txt`, `srt`, `vtt` |
| `-l`, `-lang` | `auto` | ISO 639-1 code, or `auto` to detect |
| `-m`, `-model` | `large-v3-turbo` | ggml model name |
| `-summary` | `none` | `none`, `auto`, `resumen`, or `minuta` |
| `-threads` | number of CPUs | decoding threads |
| `-keep-wav` | off | keep the intermediate 16 kHz WAV |
| `-json` | off | report progress as one JSON object per line on stdout |

`-json` is what the app reads. It also silences whisper-cli's own narration,
which a caller reading the event stream has no use for and which runs to
megabytes of decoded segments for a long recording. Without `-json`, stdout
carries the bare output paths and stderr the human narration, whisper-cli's
included, exactly as before:

```sh
transcribe -json reunion.opus
{"event":"input","name":"reunion.opus","duration_ms":963000}
{"event":"stage","stage":"transcribe"}
{"event":"progress","percent":37}
{"event":"transcript","language":"es","segments":167,"elapsed_ms":103000}
{"event":"output","kind":"txt","path":"/…/reunion.txt"}
```

`-summary` drives the `claude` CLI, so it needs Claude Code installed and
signed in — no API key. Its presence is checked before transcription starts, so
a missing dependency fails immediately rather than after the decode.

The three kinds differ in who chooses the shape. `resumen` is a paragraph plus
key points and `minuta` is always topics, decisions and action items, whatever
the recording held. `auto` decides from the recording: it lists the facts it can
support before writing anything, tagged as decisions, commitments, open
questions, risks, underlying needs or context, and the sections that appear are
the ones those facts earned. A call that ended in disagreement gets its open
questions; a voice note gets neither those nor an empty heading standing in for
them. Where the material supports it, `auto` closes with what the stated request
appears to be after, marked as a reading rather than as something said.

An input that is already a transcript — `.txt`, `.srt` or `.vtt` — skips ffmpeg
and whisper and only writes the summary next to it, which takes seconds instead
of a decode. Subtitles are the better input of the three: they still carry the
segment timings, which the summary uses to follow the order of the conversation.

## How it works

`ffmpeg` normalizes any input container to the 16 kHz mono 16-bit WAV that
whisper.cpp requires, `whisper-cli` transcribes it, and the JSON it writes is
rendered as text or subtitles. `-summary` sends the transcript to `claude
--print`, timestamped and above the instruction that acts on it.

Every stage is an external binary, so the Go module itself has no dependencies
outside the standard library. The app follows the same rule: it uses only
system frameworks, spawns `ffmpeg` to encode, and spawns the `transcribe` binary
embedded in its bundle to do everything after the recording exists. The two
front ends therefore cannot drift apart — there is one pipeline.

Transcription sits behind the `asr.Transcriber` interface, so an in-process cgo
backend or a cloud backend can replace the subprocess without touching the rest
of the pipeline.

## Test

```sh
make test
```

Go covers the whisper JSON parser, the three output formats, argument parsing,
the progress-line parser and both event emitters. Swift covers the event decoder
on the other side of that boundary, session naming, listing and renaming, the
file a session's audio resolves to, the metadata sidecar, the status a session
derives from its files, the date labels the rows show, how imports are named,
and the mapping from preferences to CLI flags. None of them need ffmpeg,
whisper-cli, a model, audio hardware, or the network.

`make test-swift` passes extra flags because swift-testing ships inside the
Command Line Tools but is not on the default search paths. With Xcode installed
they would be unnecessary.

`app/spike/` is the standalone program that proved process taps work here before
the app was written. It stays as a diagnostic: if a macOS update breaks system
audio capture, `sh app/spike/build.sh && open bin/AudioSpike.app` answers whether
the problem is Core Audio or this app.

## Release

Releases are built on the maintainer's machine and published as GitHub
Releases; there is no CI. Once, install and sign in to the GitHub CLI and
create the remote:

```sh
brew install gh && gh auth login
gh repo create santiagomilos/record-transcriber --public --source . --remote origin --push
```

Then, for every version:

```sh
make release VERSION=0.2.0
```

`make release` refuses to run without `gh`, without an `origin`, off `main`,
with uncommitted changes, or if the tag already exists. It then runs the tests,
builds the app with the version stamped into its `Info.plist` (build number =
commit count), verifies the signature and that both binaries are arm64, zips
the bundle with `ditto` into `dist/Record-Transcriber-arm64.zip`, tags
`v0.2.0`, pushes `main` and the tag, and creates the release with the zip
attached and notes made from the commit subjects since the previous tag. The
asset name never changes, which is what lets `install.sh` fetch
`releases/latest/download/Record-Transcriber-arm64.zip` without asking the
API.

If publishing fails after the tag was pushed, rerun only the last step:

```sh
gh release create v0.2.0 --verify-tag --title "Record Transcriber 0.2.0" \
  --notes-file dist/notes.md "dist/Record-Transcriber-arm64.zip#Record Transcriber 0.2.0 (Apple Silicon)"
```

`make dist VERSION=x.y.z` builds the zip without publishing, and
`RECORD_TRANSCRIBER_ZIP=dist/Record-Transcriber-arm64.zip RECORD_TRANSCRIBER_DEST=/some/folder bash install.sh`
exercises the install path against it before any release exists.
