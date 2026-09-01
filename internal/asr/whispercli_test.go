package asr

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestParseWhisperJSONReadsLanguageAndSegments(t *testing.T) {
	data, err := os.ReadFile("testdata/whisper-output.json")
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}

	got, err := ParseWhisperJSON(data)
	if err != nil {
		t.Fatalf("ParseWhisperJSON returned error: %v", err)
	}

	if got.Language != "es" {
		t.Errorf("Language = %q, want %q", got.Language, "es")
	}
	if len(got.Segments) != 3 {
		t.Fatalf("got %d segments, want 3", len(got.Segments))
	}

	want := []Segment{
		{Start: 0, End: 4*time.Second + 120*time.Millisecond, Text: "Buenos días a todos."},
		{Start: 59*time.Second + 500*time.Millisecond, End: 63 * time.Second, Text: "Pasemos al segundo punto."},
		{Start: time.Hour + 2*time.Minute, End: time.Hour + 2*time.Minute + 900*time.Millisecond, Text: "Gracias, nos vemos."},
	}
	for i, w := range want {
		if got.Segments[i] != w {
			t.Errorf("segment %d = %+v, want %+v", i, got.Segments[i], w)
		}
	}
}

func TestParseWhisperJSONTrimsLeadingSpace(t *testing.T) {
	got, err := ParseWhisperJSON([]byte(`{
		"result": {"language": "en"},
		"transcription": [{"offsets": {"from": 0, "to": 1000}, "text": "  Hello there.  "}]
	}`))
	if err != nil {
		t.Fatalf("ParseWhisperJSON returned error: %v", err)
	}
	if got.Segments[0].Text != "Hello there." {
		t.Errorf("Text = %q, want %q", got.Segments[0].Text, "Hello there.")
	}
}

func TestParseWhisperJSONRejectsEmptyTranscription(t *testing.T) {
	_, err := ParseWhisperJSON([]byte(`{"result": {"language": "es"}, "transcription": []}`))
	if err == nil {
		t.Fatal("expected an error for a transcript with no segments, got nil")
	}
}

func TestParseWhisperJSONRejectsMalformedInput(t *testing.T) {
	_, err := ParseWhisperJSON([]byte(`{"transcription": [`))
	if err == nil {
		t.Fatal("expected an error for malformed json, got nil")
	}
}

func TestTranscribeRejectsVADWithoutVADModel(t *testing.T) {
	w := &WhisperCLI{}
	_, err := w.Transcribe(context.Background(), "audio.wav", Options{
		ModelPath: "model.bin",
		VAD:       true,
	})
	if err == nil {
		t.Fatal("expected an error when VAD is on with no VAD model, got nil")
	}
}

func TestTranscribeRejectsMissingModelPath(t *testing.T) {
	w := &WhisperCLI{}
	if _, err := w.Transcribe(context.Background(), "audio.wav", Options{}); err == nil {
		t.Fatal("expected an error with no model path, got nil")
	}
}

func TestTranscribeRejectsEmptyWavPath(t *testing.T) {
	w := &WhisperCLI{}
	if _, err := w.Transcribe(context.Background(), "", Options{ModelPath: "model.bin"}); err == nil {
		t.Fatal("expected an error with an empty wav path, got nil")
	}
}

func TestResultTextJoinsSegmentsWithSpaces(t *testing.T) {
	r := &Result{Segments: []Segment{
		{Text: "Buenos días."},
		{Text: "Empecemos."},
	}}
	if got := r.Text(); got != "Buenos días. Empecemos." {
		t.Errorf("Text() = %q, want %q", got, "Buenos días. Empecemos.")
	}
}

func TestResultTextWithNoSegmentsIsEmpty(t *testing.T) {
	r := &Result{}
	if got := r.Text(); got != "" {
		t.Errorf("Text() = %q, want empty", got)
	}
}
