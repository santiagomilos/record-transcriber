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

	// Everything that can fail without doing work fails here, so a missing
	// dependency or credential surfaces in a second rather than after a long
	// transcription.
	if err := checkDependencies(); err != nil {
		return err
	}
	if _, err := os.Stat(cfg.input); err != nil {
		return fmt.Errorf("cannot read input file: %w", err)
	}
	if cfg.summaryKind != summary.KindNone {
		if err := summary.CheckAvailable(); err != nil {
			return err
		}
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	modelPath, err := modelstore.EnsureModel(ctx, cfg.model, os.Stderr)
	if err != nil {
		return err
	}
	vadModelPath, err := modelstore.EnsureModel(ctx, modelstore.VADModel, os.Stderr)
	if err != nil {
		return err
	}

	wavPath, cleanup, err := prepareAudio(ctx, cfg)
	if err != nil {
		return err
	}
	defer cleanup()

	fmt.Fprintln(os.Stderr, "Transcribing...")
	started := time.Now()

	transcriber := &asr.WhisperCLI{Stderr: os.Stderr}
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

	fmt.Fprintf(os.Stderr, "Done in %s (language: %s, %d segments)\n",
		time.Since(started).Round(time.Second), result.Language, len(result.Segments))

	written, err := writeOutputs(cfg, result)
	if err != nil {
		return err
	}

	if cfg.summaryKind != summary.KindNone {
		fmt.Fprintf(os.Stderr, "Generating %s...\n", cfg.summaryKind)
		text, err := summary.Generate(ctx, result, cfg.summaryKind)
		if err != nil {
			return err
		}
		path := cfg.outputBase + ".summary.md"
		if err := os.WriteFile(path, []byte(text+"\n"), 0o644); err != nil {
			return fmt.Errorf("write %s: %w", path, err)
		}
		written = append(written, path)
	}

	for _, path := range written {
		fmt.Println(path)
	}
	return nil
}

func parseArgs(args []string) (config, error) {
	fs := flag.NewFlagSet("transcribe", flag.ContinueOnError)
	fs.Usage = func() {
		fmt.Fprintf(fs.Output(), "Usage: transcribe <audio-or-video-file> [flags]\n\nFlags:\n")
		fs.PrintDefaults()
	}

	output := fs.String("output", "", "base path for output files (default: the input file's path without its extension)")
	formats := fs.String("format", "txt,srt", "comma-separated output formats: txt, srt, vtt")
	language := fs.String("lang", "auto", "ISO 639-1 language code, or \"auto\" to detect")
	model := fs.String("model", modelstore.DefaultModel, "ggml model name")
	summaryFlag := fs.String("summary", "none", "generate a summary from the transcript: none, resumen or minuta")
	threads := fs.Int("threads", runtime.NumCPU(), "decoding threads")
	keepWAV := fs.Bool("keep-wav", false, "keep the intermediate 16 kHz WAV file")

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

	return config{
		input:       input,
		outputBase:  base,
		formats:     parsedFormats,
		language:    *language,
		model:       *model,
		summaryKind: kind,
		threads:     *threads,
		keepWAV:     *keepWAV,
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
func prepareAudio(ctx context.Context, cfg config) (string, func(), error) {
	noop := func() {}

	if seconds, err := media.Duration(ctx, cfg.input); err == nil && seconds > 0 {
		fmt.Fprintf(os.Stderr, "Input: %s (%s)\n",
			filepath.Base(cfg.input), (time.Duration(seconds) * time.Second).Round(time.Second))
	}

	wavPath := cfg.outputBase + ".16k.wav"
	fmt.Fprintln(os.Stderr, "Extracting audio...")
	if err := media.ExtractAudio(ctx, cfg.input, wavPath); err != nil {
		return "", noop, err
	}

	if cfg.keepWAV {
		return wavPath, noop, nil
	}
	return wavPath, func() { os.Remove(wavPath) }, nil
}

func writeOutputs(cfg config, result *asr.Result) ([]string, error) {
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
		written = append(written, path)
	}
	return written, nil
}
