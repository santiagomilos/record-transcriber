# record-transcriber

Turns an audio or video recording into text, locally. The audio never leaves the
machine and there is no per-hour cost.

## Install

```sh
brew install ffmpeg whisper-cpp
go build -o bin/transcribe ./cmd/transcribe
```

Models are downloaded on first run into `~/Library/Caches/record-transcriber/models/`
on macOS (`~/.cache/...` on Linux): the transcription model, `large-v3-turbo` at
1.6 GB, plus a small Silero voice-activity model used to skip silence.

## Use

```sh
# transcript as .txt and .srt next to the input file
transcribe reunion.mp4

# subtitles only, forcing Spanish instead of detecting it
transcribe -f srt,vtt -l es reunion.mp4

# transcript plus structured meeting minutes from Claude
transcribe --summary minuta reunion.mp4
```

| Flag | Default | Meaning |
|---|---|---|
| `-o`, `-output` | input path without its extension | base path for output files |
| `-f`, `-format` | `txt,srt` | any of `txt`, `srt`, `vtt` |
| `-l`, `-lang` | `auto` | ISO 639-1 code, or `auto` to detect |
| `-m`, `-model` | `large-v3-turbo` | ggml model name |
| `-summary` | `none` | `none`, `resumen`, or `minuta` |
| `-threads` | number of CPUs | decoding threads |
| `-keep-wav` | off | keep the intermediate 16 kHz WAV |

`--summary` drives the `claude` CLI, so it needs Claude Code installed and
signed in — no API key. Its presence is checked before transcription starts, so
a missing dependency fails immediately rather than after the decode.

## How it works

`ffmpeg` normalizes any input container to the 16 kHz mono 16-bit WAV that
whisper.cpp requires, `whisper-cli` transcribes it, and the JSON it writes is
rendered as text or subtitles. `--summary` pipes the transcript into `claude
--print`.

Every stage is an external binary, so the Go module itself has no dependencies
outside the standard library.

Transcription sits behind the `asr.Transcriber` interface, so an in-process cgo
backend or a cloud backend can replace the subprocess without touching the rest
of the pipeline.

## Test

```sh
go test ./...
```

The tests cover the whisper JSON parser, the three output formats, and argument
parsing. None of them need ffmpeg, whisper-cli, a model, or the network.
