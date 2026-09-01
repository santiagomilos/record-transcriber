package asr

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// BinaryName is the whisper.cpp executable this backend drives.
const BinaryName = "whisper-cli"

// WhisperCLI transcribes by invoking the whisper-cli binary as a subprocess.
type WhisperCLI struct {
	// Binary is the executable to run; empty means BinaryName from $PATH.
	Binary string
	// Stdout, when set, receives the segments whisper-cli prints as it decodes
	// them. Leaving it nil discards them: they run to megabytes for a long
	// recording, and the transcript itself arrives through --output-json.
	Stdout io.Writer
	// Stderr, when set, receives whisper-cli's diagnostics, which is also where
	// it writes its progress reports. The tail of them is kept for the error
	// message whether or not this is set.
	Stderr io.Writer
	// Progress, when set, is called with the decoding percentage as whisper-cli
	// reports it. Setting it also turns on --print-progress, so leaving it nil
	// keeps the subprocess's output exactly as it is without one.
	Progress func(percent int)
}

// Transcribe runs whisper-cli over wavPath and parses its JSON output.
func (w *WhisperCLI) Transcribe(ctx context.Context, wavPath string, opts Options) (*Result, error) {
	if wavPath == "" {
		return nil, errors.New("asr: empty wav path")
	}
	if opts.ModelPath == "" {
		return nil, errors.New("asr: no model path configured")
	}
	// whisper-cli aborts rather than falling back when --vad is passed without
	// a model, so reject the combination here where the error is legible.
	if opts.VAD && opts.VADModelPath == "" {
		return nil, errors.New("asr: VAD requested without a VAD model path")
	}

	// whisper-cli writes its output next to -of rather than to stdout, so it
	// needs a scratch directory we control and clean up.
	tmpDir, err := os.MkdirTemp("", "record-transcriber-asr-")
	if err != nil {
		return nil, fmt.Errorf("asr: create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	outBase := filepath.Join(tmpDir, "out")

	lang := opts.Language
	if lang == "" {
		lang = "auto"
	}

	args := []string{
		"--model", opts.ModelPath,
		"--file", wavPath,
		"--language", lang,
		"--output-json",
		"--output-file", outBase,
	}
	if opts.Threads > 0 {
		args = append(args, "--threads", fmt.Sprint(opts.Threads))
	}
	if opts.VAD {
		args = append(args, "--vad", "--vad-model", opts.VADModelPath)
	}
	if w.Progress != nil {
		args = append(args, "--print-progress")
	}

	bin := w.Binary
	if bin == "" {
		bin = BinaryName
	}

	// The tail is captured whichever way the caller wants the stream routed: it
	// is what says why a run failed, and a caller forwarding the stream
	// elsewhere has no way to hand it back here.
	var tail tailBuffer
	var diagnostics io.Writer = &tail
	if w.Stderr != nil {
		diagnostics = io.MultiWriter(&tail, w.Stderr)
	}

	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Stdout = w.Stdout
	cmd.Stderr = w.watchProgress(diagnostics)

	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(tail.String()); msg != "" {
			return nil, fmt.Errorf("asr: %s failed: %w: %s", bin, err, msg)
		}
		return nil, fmt.Errorf("asr: %s failed: %w", bin, err)
	}

	data, err := os.ReadFile(outBase + ".json")
	if err != nil {
		return nil, fmt.Errorf("asr: read %s output: %w", bin, err)
	}
	return ParseWhisperJSON(data)
}

// watchProgress wraps out so whisper-cli's progress lines are reported while
// everything it writes still reaches out unchanged.
func (w *WhisperCLI) watchProgress(out io.Writer) io.Writer {
	if w.Progress == nil {
		return out
	}
	return &progressScanner{out: out, report: w.Progress}
}

// progressScanner forwards every byte written to it while pulling whisper-cli's
// progress reports out of the stream. whisper-cli writes them to stderr among
// the rest of its diagnostics rather than on a stream of their own, so they are
// recognised by their prefix.
type progressScanner struct {
	out     io.Writer
	report  func(percent int)
	partial []byte
}

func (p *progressScanner) Write(b []byte) (int, error) {
	p.partial = append(p.partial, b...)
	for {
		end := bytes.IndexByte(p.partial, '\n')
		if end < 0 {
			break
		}
		if percent := parseProgressLine(string(p.partial[:end])); percent >= 0 {
			p.report(percent)
		}
		p.partial = append(p.partial[:0], p.partial[end+1:]...)
	}
	return p.out.Write(b)
}

// progressPrefix is what whisper-cli writes before each percentage once it is
// given --print-progress.
const progressPrefix = "whisper_print_progress_callback: progress ="

// parseProgressLine returns the percentage a whisper-cli progress line reports,
// or -1 for any other line.
func parseProgressLine(line string) int {
	rest, ok := strings.CutPrefix(strings.TrimSpace(line), progressPrefix)
	if !ok {
		return -1
	}
	rest, ok = strings.CutSuffix(strings.TrimSpace(rest), "%")
	if !ok {
		return -1
	}
	percent, err := strconv.Atoi(strings.TrimSpace(rest))
	if err != nil || percent < 0 || percent > 100 {
		return -1
	}
	return percent
}

// maxTailBytes bounds what tailBuffer keeps. whisper-cli opens with a hundred
// or so lines of model and system detail, and only the end of the stream says
// why a run failed.
const maxTailBytes = 8 << 10

// tailBuffer keeps the last maxTailBytes bytes written to it and drops the rest,
// so a subprocess that narrates for an hour still costs a fixed amount of memory.
type tailBuffer struct {
	buf []byte
}

func (t *tailBuffer) Write(b []byte) (int, error) {
	t.buf = append(t.buf, b...)
	if extra := len(t.buf) - maxTailBytes; extra > 0 {
		t.buf = append(t.buf[:0], t.buf[extra:]...)
	}
	// io.MultiWriter treats a short count as an error, so the report is of what
	// the caller wrote rather than of what was kept.
	return len(b), nil
}

func (t *tailBuffer) String() string { return string(t.buf) }

// whisperJSON mirrors the subset of whisper.cpp's --output-json document that
// we consume. Timestamps are read from offsets (milliseconds) rather than the
// preformatted "timestamps" strings.
type whisperJSON struct {
	Result struct {
		Language string `json:"language"`
	} `json:"result"`
	Transcription []struct {
		Offsets struct {
			From int64 `json:"from"`
			To   int64 `json:"to"`
		} `json:"offsets"`
		Text string `json:"text"`
	} `json:"transcription"`
}

// ParseWhisperJSON decodes a whisper.cpp --output-json document.
func ParseWhisperJSON(data []byte) (*Result, error) {
	var doc whisperJSON
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("asr: decode whisper json: %w", err)
	}
	if len(doc.Transcription) == 0 {
		return nil, errors.New("asr: whisper produced no speech segments")
	}

	segments := make([]Segment, 0, len(doc.Transcription))
	for _, t := range doc.Transcription {
		segments = append(segments, Segment{
			Start: time.Duration(t.Offsets.From) * time.Millisecond,
			End:   time.Duration(t.Offsets.To) * time.Millisecond,
			// whisper prefixes every segment with a space.
			Text: strings.TrimSpace(t.Text),
		})
	}
	return &Result{Language: doc.Result.Language, Segments: segments}, nil
}
