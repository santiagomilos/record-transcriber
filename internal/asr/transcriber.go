// Package asr turns a prepared audio file into a timestamped transcript.
package asr

import (
	"context"
	"time"
)

// Segment is one timestamped chunk of speech, with offsets relative to the
// start of the audio.
type Segment struct {
	Start time.Duration
	End   time.Duration
	Text  string
}

// Result is a complete transcript.
type Result struct {
	// Language is the ISO 639-1 code the engine detected or was told to use.
	Language string
	Segments []Segment
}

// Text joins every segment into a single block of prose.
func (r *Result) Text() string {
	if len(r.Segments) == 0 {
		return ""
	}
	out := r.Segments[0].Text
	for _, s := range r.Segments[1:] {
		out += " " + s.Text
	}
	return out
}

// Options configures a single transcription run.
type Options struct {
	// Language is an ISO 639-1 code, or "auto"/"" to let the engine detect it.
	Language string
	// ModelPath points at a ggml model file on disk.
	ModelPath string
	// Threads is the number of decoding threads; zero lets the engine decide.
	Threads int
	// VAD skips silent regions, which speeds up recordings with long pauses.
	// It requires VADModelPath.
	VAD bool
	// VADModelPath points at a Silero VAD ggml model.
	VADModelPath string
}

// Transcriber is the engine boundary. The only implementation today shells out
// to whisper-cli; an in-process cgo backend would satisfy the same contract.
type Transcriber interface {
	// Transcribe reads a 16 kHz mono 16-bit WAV file and returns its transcript.
	Transcribe(ctx context.Context, wavPath string, opts Options) (*Result, error)
}
