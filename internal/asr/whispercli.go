package asr

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// BinaryName is the whisper.cpp executable this backend drives.
const BinaryName = "whisper-cli"

// WhisperCLI transcribes by invoking the whisper-cli binary as a subprocess.
type WhisperCLI struct {
	// Binary is the executable to run; empty means BinaryName from $PATH.
	Binary string
	// Stderr, when set, receives whisper-cli's progress output.
	Stderr *os.File
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

	bin := w.Binary
	if bin == "" {
		bin = BinaryName
	}

	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, bin, args...)
	if w.Stderr != nil {
		// whisper-cli prints each segment to stdout as it decodes; routing it
		// here surfaces progress without polluting our own stdout, which
		// carries the output paths for callers that pipe them.
		cmd.Stdout = w.Stderr
		cmd.Stderr = w.Stderr
	} else {
		cmd.Stderr = &stderr
	}

	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
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
