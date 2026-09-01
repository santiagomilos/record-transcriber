# Tech Stack

## Frontend

N/A — command-line tool.

## Backend

Go 1.27, standard library only — no third-party modules. `flag` for argument parsing, `os/exec` for driving the external binaries, `encoding/json` for reading whisper's output, `net/http` for fetching models.

Every capability the tool does not implement itself comes from a binary it shells out to, which is why the dependency list is empty.

## Database

N/A — the tool reads a file and writes files. The only persistent state is the model cache under `~/.cache/record-transcriber/models/`.

## Other

**External binaries** (installed via Homebrew, checked at startup):

- `ffmpeg` / `ffprobe` — normalize any input container to the 16 kHz mono 16-bit WAV that whisper requires.
- `whisper-cli` from the `whisper-cpp` formula — the transcription engine.
- `claude` (Claude Code) — summaries and meeting minutes, driven as `claude --print` with the transcript on stdin. Going through the CLI rather than the HTTP API means summaries are covered by an existing Claude Code subscription and need no API key.

**Models:** ggml models downloaded from Hugging Face and cached under the user cache directory (`~/Library/Caches/record-transcriber/models/` on macOS). Two are needed: `large-v3-turbo` (1.6 GB) for transcription, chosen for its speed-to-accuracy tradeoff on Apple Silicon, and the Silero `silero-v5.1.2` voice-activity model that `whisper-cli --vad` requires. They live in different Hugging Face repositories (`ggerganov/whisper.cpp` and `ggml-org/whisper-vad`).

**Configuration:** none. The tool reads no config file and no environment variables; summaries inherit whatever account and model the installed Claude Code is already signed in with.
