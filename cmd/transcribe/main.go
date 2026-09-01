// Command transcribe turns an audio or video recording into text.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/santi/record-transcriber/internal/asr"
	"github.com/santi/record-transcriber/internal/format"
	"github.com/santi/record-transcriber/internal/media"
	"github.com/santi/record-transcriber/internal/modelstore"
	"github.com/santi/record-transcriber/internal/progress"
	"github.com/santi/record-transcriber/internal/summary"
)

type config struct {
	input       string
	outputBase  string
	formats     []string
	language    string
	model       string
	summaryKind summary.Kind
	threads     int
	keepWAV     bool
	jsonEvents  bool
	// fromTranscript marks an input that is already text, which skips ffmpeg and
	// whisper entirely and leaves the summary as the only thing to produce.
	fromTranscript bool
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := parseArgs(os.Args[1:])
	if err != nil {
		return err
	}

	// stdout carries the machine-readable result and stderr the narration, in
	// both modes. -json swaps bare output paths on stdout for a live event
	// stream that already contains them.
	var events progress.Emitter = &progress.Text{W: os.Stderr}
	if cfg.jsonEvents {
		events = &progress.JSON{W: os.Stdout}
	}

	if err := transcribe(cfg, events); err != nil {
		events.Emit(progress.Error(err))
		return err
	}
	return nil
}

func transcribe(cfg config, events progress.Emitter) error {
	// Everything that can fail without doing work fails here, so a missing
	// dependency or credential surfaces in a second rather than after a long
	// transcription.
	if _, err := os.Stat(cfg.input); err != nil {
		return fmt.Errorf("cannot read input file: %w", err)
	}
	if cfg.summaryKind != summary.KindNone {
		if err := summary.CheckAvailable(); err != nil {
			return err
		}
	}
	if cfg.fromTranscript {
		return summarizeTranscript(cfg, events)
	}
	if err := checkDependencies(); err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	report := func(d modelstore.Download) {
		events.Emit(progress.Model(d.Model, d.BytesDone, d.BytesTotal, d.Done))
	}
	modelPath, err := modelstore.EnsureModel(ctx, cfg.model, report)
	if err != nil {
		return err
	}
	vadModelPath, err := modelstore.EnsureModel(ctx, modelstore.VADModel, report)
	if err != nil {
		return err
	}

	wavPath, cleanup, err := prepareAudio(ctx, cfg, events)
	if err != nil {
		return err
	}
	defer cleanup()

	events.Emit(progress.Stage(progress.StageTranscribe))
	started := time.Now()

	transcriber := &asr.WhisperCLI{Stderr: os.Stderr}
	if cfg.jsonEvents {
		// Only in JSON mode: --print-progress would otherwise add lines to the
		// output a terminal user sees today.
		transcriber.Progress = func(percent int) { events.Emit(progress.Progress(percent)) }
	}
	result, err := transcriber.Transcribe(ctx, wavPath, asr.Options{
		Language:     cfg.language,
		ModelPath:    modelPath,
		Threads:      cfg.threads,
		VAD:          true,
		VADModelPath: vadModelPath,
	})
	if err != nil {
		return err
	}

	events.Emit(progress.Transcript(result.Language, len(result.Segments), time.Since(started)))

	written, err := writeOutputs(cfg, result, events)
	if err != nil {
		return err
	}

	if cfg.summaryKind != summary.KindNone {
		events.Emit(progress.Summary(string(cfg.summaryKind)))
		text, err := summary.Generate(ctx, result, cfg.summaryKind)
		if err != nil {
			return err
		}
		path := cfg.outputBase + ".summary.md"
		if err := os.WriteFile(path, []byte(text+"\n"), 0o644); err != nil {
			return fmt.Errorf("write %s: %w", path, err)
		}
		events.Emit(progress.Output("summary", path))
		written = append(written, path)
	}

	// The event stream already announced every path, so printing them again
	// would break the one-JSON-object-per-line contract.
	if !cfg.jsonEvents {
		for _, path := range written {
			fmt.Println(path)
		}
	}
	return nil
}

// summarizeTranscript summarizes a transcript that already exists, skipping the
// decode. It writes no transcript files: the input is one, and the output base
// derived from it would name the file it was read from.
func summarizeTranscript(cfg config, events progress.Emitter) error {
	result, err := readTranscript(cfg.input)
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	events.Emit(progress.Summary(string(cfg.summaryKind)))
	text, err := summary.Generate(ctx, result, cfg.summaryKind)
	if err != nil {
		return err
	}

	path := cfg.outputBase + ".summary.md"
	if err := os.WriteFile(path, []byte(text+"\n"), 0o644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	events.Emit(progress.Output("summary", path))
	if !cfg.jsonEvents {
		fmt.Println(path)
	}
	return nil
}

// readTranscript reads back a transcript this tool wrote earlier. Subtitles are
// preferred over plain text because they still carry the segment timings, which
// the summary prompt uses to follow the order of the conversation.
func readTranscript(path string) (*asr.Result, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("cannot read transcript: %w", err)
	}
	defer f.Close()

	var result *asr.Result
	switch strings.ToLower(filepath.Ext(path)) {
	case ".srt", ".vtt":
		// Both are cue blocks separated by blank lines; the VTT header carries no
		// "-->" and is skipped like a cue number.
		result, err = format.ReadSRT(f)
	default:
		result, err = format.ReadText(f)
	}
	if err != nil {
		return nil, fmt.Errorf("cannot read transcript %s: %w", path, err)
	}
	return result, nil
}

// transcriptExtensions are the inputs that are already text. Everything else is
// handed to ffmpeg, which is what decides whether it is media at all.
var transcriptExtensions = map[string]bool{".txt": true, ".srt": true, ".vtt": true}

func parseArgs(args []string) (config, error) {
	fs := flag.NewFlagSet("transcribe", flag.ContinueOnError)
	fs.Usage = func() {
		fmt.Fprintf(fs.Output(), "Usage: transcribe <audio-or-video-file> [flags]\n"+
			"       transcribe <transcript.txt|.srt|.vtt> -summary <kind> [flags]\n\nFlags:\n")
		fs.PrintDefaults()
	}

	output := fs.String("output", "", "base path for output files (default: the input file's path without its extension)")
	formats := fs.String("format", "txt,srt", "comma-separated output formats: txt, srt, vtt")
	language := fs.String("lang", "auto", "ISO 639-1 language code, or \"auto\" to detect")
	model := fs.String("model", modelstore.DefaultModel, "ggml model name")
	summaryFlag := fs.String("summary", "none", "generate a summary from the transcript: none, auto, resumen or minuta")
	threads := fs.Int("threads", runtime.NumCPU(), "decoding threads")
	keepWAV := fs.Bool("keep-wav", false, "keep the intermediate 16 kHz WAV file")
	jsonEvents := fs.Bool("json", false, "report progress as one JSON object per line on stdout, for a program driving this tool")

	fs.StringVar(output, "o", "", "shorthand for -output")
	fs.StringVar(formats, "f", "txt,srt", "shorthand for -format")
	fs.StringVar(language, "l", "auto", "shorthand for -lang")
	fs.StringVar(model, "m", modelstore.DefaultModel, "shorthand for -model")

	if err := fs.Parse(args); err != nil {
		return config{}, err
	}
	if fs.NArg() != 1 {
		fs.Usage()
		return config{}, errors.New("expected exactly one input file")
	}

	parsedFormats, err := parseFormats(*formats)
	if err != nil {
		return config{}, err
	}
	kind, err := summary.ParseKind(*summaryFlag)
	if err != nil {
		return config{}, err
	}

	input := fs.Arg(0)
	base := *output
	if base == "" {
		base = outputBaseFor(input)
	}

	fromTranscript := transcriptExtensions[strings.ToLower(filepath.Ext(input))]
	if fromTranscript && kind == summary.KindNone {
		return config{}, errors.New("the input is already a transcript, so -summary is what this run would produce; pass one of auto, resumen or minuta")
	}

	return config{
		input:          input,
		outputBase:     base,
		formats:        parsedFormats,
		language:       *language,
		model:          *model,
		summaryKind:    kind,
		threads:        *threads,
		keepWAV:        *keepWAV,
		jsonEvents:     *jsonEvents,
		fromTranscript: fromTranscript,
	}, nil
}

// parseFormats validates a comma-separated format list, preserving order and
// dropping duplicates.
func parseFormats(s string) ([]string, error) {
	var out []string
	seen := map[string]bool{}
	for _, raw := range strings.Split(s, ",") {
		name := strings.ToLower(strings.TrimSpace(raw))
		if name == "" {
			continue
		}
		switch name {
		case "txt", "srt", "vtt":
		default:
			return nil, fmt.Errorf("unknown format %q (want txt, srt or vtt)", name)
		}
		if !seen[name] {
			seen[name] = true
			out = append(out, name)
		}
	}
	if len(out) == 0 {
		return nil, errors.New("no output formats requested")
	}
	return out, nil
}

// outputBaseFor strips the extension so "~/talk.mp4" yields "~/talk".
func outputBaseFor(input string) string {
	return strings.TrimSuffix(input, filepath.Ext(input))
}

func checkDependencies() error {
	for _, dep := range []struct{ binary, install string }{
		{media.FFmpegBinary, "brew install ffmpeg"},
		{media.FFprobeBinary, "brew install ffmpeg"},
		{asr.BinaryName, "brew install whisper-cpp"},
	} {
		if _, err := exec.LookPath(dep.binary); err != nil {
			return fmt.Errorf("%s is not on your PATH — install it with: %s", dep.binary, dep.install)
		}
	}
	return nil
}

// prepareAudio produces the 16 kHz mono WAV whisper needs, and returns a
// cleanup func that removes it unless --keep-wav was given.
func prepareAudio(ctx context.Context, cfg config, events progress.Emitter) (string, func(), error) {
	noop := func() {}

	if seconds, err := media.Duration(ctx, cfg.input); err == nil && seconds > 0 {
		events.Emit(progress.Input(filepath.Base(cfg.input), time.Duration(seconds)*time.Second))
	}

	wavPath := cfg.outputBase + ".16k.wav"
	events.Emit(progress.Stage(progress.StageExtract))
	if err := media.ExtractAudio(ctx, cfg.input, wavPath); err != nil {
		return "", noop, err
	}

	if cfg.keepWAV {
		return wavPath, noop, nil
	}
	return wavPath, func() { os.Remove(wavPath) }, nil
}

func writeOutputs(cfg config, result *asr.Result, events progress.Emitter) ([]string, error) {
	writers := map[string]func(*os.File, *asr.Result) error{
		"txt": func(f *os.File, r *asr.Result) error { return format.WriteText(f, r) },
		"srt": func(f *os.File, r *asr.Result) error { return format.WriteSRT(f, r) },
		"vtt": func(f *os.File, r *asr.Result) error { return format.WriteVTT(f, r) },
	}

	var written []string
	for _, name := range cfg.formats {
		path := cfg.outputBase + "." + name
		f, err := os.Create(path)
		if err != nil {
			return written, fmt.Errorf("create %s: %w", path, err)
		}
		if err := writers[name](f, result); err != nil {
			f.Close()
			return written, fmt.Errorf("write %s: %w", path, err)
		}
		if err := f.Close(); err != nil {
			return written, fmt.Errorf("close %s: %w", path, err)
		}
		events.Emit(progress.Output(name, path))
		written = append(written, path)
	}
	return written, nil
}
