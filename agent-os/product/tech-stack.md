# Tech Stack

## Frontend

`Record Transcriber.app` — a native macOS app in SwiftUI, no third-party packages, built with Swift Package Manager against the SDK that ships with the Command Line Tools. Xcode is not required and no `.xcodeproj` exists: a `Makefile` assembles the bundle and signs it ad-hoc, so the whole build is reviewable text.

Recording uses Core Audio directly. A process tap (`AudioHardwareCreateProcessTap`, native since macOS 14.4) captures system audio with no virtual audio driver, and goes into one aggregate device together with the default input so Core Audio handles clock synchronization between the two sources. The mixed mono stream is piped into `ffmpeg` and written as Opus at 32 kbps.

The app does not reimplement the pipeline. It spawns the `transcribe` binary embedded in its own bundle with `-json`, and renders the event stream that comes back.

The app is **not sandboxed**: it spawns Homebrew binaries and writes into the user's Documents folder, both of which the App Sandbox forbids. That rules out the Mac App Store, which was never a goal.

## Backend

Go 1.27, standard library only — no third-party modules. `flag` for argument parsing, `os/exec` for driving the external binaries, `encoding/json` for reading whisper's output and for writing the `-json` event stream, `net/http` for fetching models.

Every capability the tool does not implement itself comes from a binary it shells out to, which is why the dependency list is empty.

## Database

N/A — the tool reads a file and writes files. The only persistent state is the model cache under `~/.cache/record-transcriber/models/`.

## Other

**External binaries** (installed via Homebrew, checked at startup):

- `ffmpeg` / `ffprobe` — normalize any input container to the 16 kHz mono 16-bit WAV that whisper requires.
- `whisper-cli` from the `whisper-cpp` formula — the transcription engine.
- `claude` (Claude Code) — summaries and meeting minutes, driven as `claude --print` with the transcript on stdin. Going through the CLI rather than the HTTP API means summaries are covered by an existing Claude Code subscription and need no API key.

**Models:** ggml models downloaded from Hugging Face and cached under the user cache directory (`~/Library/Caches/record-transcriber/models/` on macOS). Two are needed: `large-v3-turbo` (1.6 GB) for transcription, chosen for its speed-to-accuracy tradeoff on Apple Silicon, and the Silero `silero-v5.1.2` voice-activity model that `whisper-cli --vad` requires. They live in different Hugging Face repositories (`ggerganov/whisper.cpp` and `ggml-org/whisper-vad`).

**Configuration:** the CLI reads no config file and no environment variables. The app stores its preferences — library folder, language, output formats, summary kind, model — in UserDefaults, and passes them to the CLI as flags. Summaries inherit whatever account and model the installed Claude Code is already signed in with.

**PATH:** an app launched from the Finder inherits `/usr/bin:/bin:/usr/sbin:/sbin`, so it finds none of these tools. The app builds the PATH for its subprocesses by asking the user's login shell (`$SHELL -l -c 'printf %s "$PATH"'`) once, and appending the Homebrew prefixes as a fallback.

Asking the shell rather than hardcoding a list is not defensive coding: Claude Code installs `claude` under `~/.local/bin`, nowhere near Homebrew's prefix. A hardcoded list found ffmpeg and whisper-cli but not `claude`, and because the CLI checks for `claude` before transcribing, the whole run aborted having written nothing.
