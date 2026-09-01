package asr

import (
	"bytes"
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

func TestParseProgressLineReadsThePercentage(t *testing.T) {
	got := parseProgressLine("whisper_print_progress_callback: progress =  35%")
	if got != 35 {
		t.Errorf("got %d, want 35", got)
	}
}

func TestParseProgressLineReadsZeroAndOneHundred(t *testing.T) {
	if got := parseProgressLine("whisper_print_progress_callback: progress = 0%"); got != 0 {
		t.Errorf("got %d, want 0", got)
	}
	if got := parseProgressLine("whisper_print_progress_callback: progress = 100%"); got != 100 {
		t.Errorf("got %d, want 100", got)
	}
}

func TestParseProgressLineRejectsLinesThatAreNotProgress(t *testing.T) {
	lines := []string{
		"",
		"[00:00:00.000 --> 00:00:04.120]   Buenos días a todos.",
		"whisper_print_progress_callback: progress = ",
		"whisper_print_progress_callback: progress = abc%",
		"whisper_print_progress_callback: progress = 35",
		"whisper_print_progress_callback: progress = 101%",
		"whisper_print_progress_callback: progress = -5%",
	}
	for _, line := range lines {
		if got := parseProgressLine(line); got != -1 {
			t.Errorf("parseProgressLine(%q) = %d, want -1", line, got)
		}
	}
}

func TestProgressScannerReportsEveryProgressLineAndForwardsTheStreamUnchanged(t *testing.T) {
	var forwarded bytes.Buffer
	var reported []int
	scanner := &progressScanner{
		out:    &forwarded,
		report: func(percent int) { reported = append(reported, percent) },
	}

	stream := "whisper_print_progress_callback: progress =  10%\n" +
		"[00:00:00.000 --> 00:00:04.120]   Buenos días a todos.\n" +
		"whisper_print_progress_callback: progress =  50%\n" +
		"whisper_print_progress_callback: progress = 100%\n"
	if _, err := scanner.Write([]byte(stream)); err != nil {
		t.Fatalf("Write returned error: %v", err)
	}

	want := []int{10, 50, 100}
	if len(reported) != len(want) {
		t.Fatalf("got %v, want %v", reported, want)
	}
	for i, percent := range want {
		if reported[i] != percent {
			t.Errorf("report %d = %d, want %d", i, reported[i], percent)
		}
	}
	if forwarded.String() != stream {
		t.Errorf("forwarded %q, want %q", forwarded.String(), stream)
	}
}

func TestProgressScannerHandlesALineSplitAcrossWrites(t *testing.T) {
	var forwarded bytes.Buffer
	var reported []int
	scanner := &progressScanner{
		out:    &forwarded,
		report: func(percent int) { reported = append(reported, percent) },
	}

	scanner.Write([]byte("whisper_print_progress_call"))
	scanner.Write([]byte("back: progress =  75"))
	scanner.Write([]byte("%\n"))

	if len(reported) != 1 || reported[0] != 75 {
		t.Errorf("got %v, want [75]", reported)
	}
	want := "whisper_print_progress_callback: progress =  75%\n"
	if forwarded.String() != want {
		t.Errorf("forwarded %q, want %q", forwarded.String(), want)
	}
}
