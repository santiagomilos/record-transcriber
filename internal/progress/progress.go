// Package progress reports what a transcription run is doing. A terminal gets
// prose; a program driving the tool gets one JSON object per line, which is why
// both renderings sit behind a single interface rather than being spelled out at
// every call site.
package progress

import (
	"encoding/json"
	"fmt"
	"io"
	"time"
)

// Event kinds.
const (
	KindInput      = "input"
	KindModel      = "model"
	KindStage      = "stage"
	KindProgress   = "progress"
	KindTranscript = "transcript"
	KindOutput     = "output"
	KindError      = "error"
)

// Stages of a run, carried by KindStage events.
const (
	StageExtract    = "extract"
	StageTranscribe = "transcribe"
	StageSummary    = "summary"
)

// Event is one thing that happened during a run. Only the fields an event kind
// defines are populated; the rest are omitted from the JSON rendering.
type Event struct {
	Event    string `json:"event"`
	Stage    string `json:"stage,omitempty"`
	Name     string `json:"name,omitempty"`
	Kind     string `json:"kind,omitempty"`
	Path     string `json:"path,omitempty"`
	Language string `json:"language,omitempty"`
	Message  string `json:"message,omitempty"`
	Segments int    `json:"segments,omitempty"`

	// Percent appears only on KindProgress, where omitting a zero is lossless:
	// a reader decoding into an int reads the absent field as the 0% it means.
	Percent int `json:"percent,omitempty"`

	BytesDone  int64 `json:"bytes_done,omitempty"`
	BytesTotal int64 `json:"bytes_total,omitempty"`
	DurationMS int64 `json:"duration_ms,omitempty"`
	ElapsedMS  int64 `json:"elapsed_ms,omitempty"`

	// Done marks the last event of a series, which lets a renderer close off a
	// progress line it has been overwriting in place.
	Done bool `json:"done,omitempty"`
}

// Input announces the file about to be processed.
func Input(name string, duration time.Duration) Event {
	return Event{Event: KindInput, Name: name, DurationMS: duration.Milliseconds()}
}

// Model reports how far the download of a ggml model has got.
func Model(name string, bytesDone, bytesTotal int64, done bool) Event {
	return Event{
		Event: KindModel, Name: name,
		BytesDone: bytesDone, BytesTotal: bytesTotal, Done: done,
	}
}

// Stage announces that a phase of the run has started.
func Stage(stage string) Event {
	return Event{Event: KindStage, Stage: stage}
}

// Summary announces the summary phase, naming the kind being generated.
func Summary(kind string) Event {
	return Event{Event: KindStage, Stage: StageSummary, Name: kind}
}

// Progress reports how far the decode has got, as a percentage.
func Progress(percent int) Event {
	return Event{Event: KindProgress, Percent: percent}
}

// Transcript reports a finished decode.
func Transcript(language string, segments int, elapsed time.Duration) Event {
	return Event{
		Event: KindTranscript, Language: language,
		Segments: segments, ElapsedMS: elapsed.Milliseconds(),
	}
}

// Output announces a file the run has written. Kind is the format name, or
// "summary".
func Output(kind, path string) Event {
	return Event{Event: KindOutput, Kind: kind, Path: path}
}

// Error announces that the run failed.
func Error(err error) Event {
	return Event{Event: KindError, Message: err.Error()}
}

// Emitter renders events. Implementations are called from a single goroutine
// and never report failures: a broken progress stream must not fail a
// transcription that otherwise succeeded.
type Emitter interface {
	Emit(Event)
}

// Text renders events as the prose the tool has always written to a terminal.
//
// It deliberately ignores KindOutput and KindError. Output paths are the CLI's
// existing contract on stdout, printed by the caller once the run has fully
// succeeded, and the final error is the caller's "error: ..." line on stderr
// alongside a non-zero exit status. Rendering them here would duplicate both.
type Text struct {
	W io.Writer

	// downloading is the model whose progress line is currently open, so the
	// banner is printed once per download rather than once per tick.
	downloading string
}

func (t *Text) Emit(e Event) {
	switch e.Event {
	case KindInput:
		fmt.Fprintf(t.W, "Input: %s (%s)\n", e.Name,
			(time.Duration(e.DurationMS) * time.Millisecond).Round(time.Second))

	case KindModel:
		if t.downloading != e.Name {
			fmt.Fprintf(t.W, "Downloading model %s (this happens once)\n", e.Name)
			t.downloading = e.Name
		}
		switch {
		case e.Done:
			fmt.Fprintln(t.W)
			t.downloading = ""
		case e.BytesDone == 0:
			// Nothing transferred yet; the banner above is the whole report.
		case e.BytesTotal > 0:
			fmt.Fprintf(t.W, "\r  %d%% (%d/%d MiB)",
				e.BytesDone*100/e.BytesTotal, e.BytesDone>>20, e.BytesTotal>>20)
		default:
			fmt.Fprintf(t.W, "\r  %d MiB", e.BytesDone>>20)
		}

	case KindStage:
		switch e.Stage {
		case StageExtract:
			fmt.Fprintln(t.W, "Extracting audio...")
		case StageTranscribe:
			fmt.Fprintln(t.W, "Transcribing...")
		case StageSummary:
			fmt.Fprintf(t.W, "Generating %s...\n", e.Name)
		}

	case KindProgress:
		fmt.Fprintf(t.W, "\r  %d%%", e.Percent)

	case KindTranscript:
		fmt.Fprintf(t.W, "Done in %s (language: %s, %d segments)\n",
			(time.Duration(e.ElapsedMS) * time.Millisecond).Round(time.Second),
			e.Language, e.Segments)
	}
}

// JSON writes one event per line, so a program driving the tool reads the run as
// it happens rather than waiting for the process to exit.
type JSON struct {
	W io.Writer
}

func (j *JSON) Emit(e Event) {
	data, err := json.Marshal(e)
	if err != nil {
		return
	}
	j.W.Write(append(data, '\n'))
}
