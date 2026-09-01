package format

import (
	"strings"
	"testing"
	"time"

	"github.com/santi/record-transcriber/internal/asr"
)

// sample spans the one-minute and one-hour boundaries so the timestamp carry
// is exercised, not just the seconds field.
func sample() *asr.Result {
	return &asr.Result{
		Language: "es",
		Segments: []asr.Segment{
			{Start: 0, End: 4*time.Second + 120*time.Millisecond, Text: "Buenos días a todos."},
			{Start: 59*time.Second + 500*time.Millisecond, End: 63 * time.Second, Text: "Pasemos al segundo punto."},
			{Start: time.Hour + 2*time.Minute, End: time.Hour + 2*time.Minute + 900*time.Millisecond, Text: "Gracias, nos vemos."},
		},
	}
}

func TestWriteTextWritesOneSegmentPerLine(t *testing.T) {
	var buf strings.Builder
	if err := WriteText(&buf, sample()); err != nil {
		t.Fatalf("WriteText returned error: %v", err)
	}

	want := "Buenos días a todos.\n" +
		"Pasemos al segundo punto.\n" +
		"Gracias, nos vemos.\n"

	if buf.String() != want {
		t.Errorf("got:\n%q\nwant:\n%q", buf.String(), want)
	}
}

func TestWriteSRTNumbersBlocksFromOneAndUsesComma(t *testing.T) {
	var buf strings.Builder
	if err := WriteSRT(&buf, sample()); err != nil {
		t.Fatalf("WriteSRT returned error: %v", err)
	}

	want := "1\n" +
		"00:00:00,000 --> 00:00:04,120\n" +
		"Buenos días a todos.\n\n" +
		"2\n" +
		"00:00:59,500 --> 00:01:03,000\n" +
		"Pasemos al segundo punto.\n\n" +
		"3\n" +
		"01:02:00,000 --> 01:02:00,900\n" +
		"Gracias, nos vemos.\n\n"

	if buf.String() != want {
		t.Errorf("got:\n%q\nwant:\n%q", buf.String(), want)
	}
}

func TestWriteVTTHasHeaderNoCueNumbersAndUsesPeriod(t *testing.T) {
	var buf strings.Builder
	if err := WriteVTT(&buf, sample()); err != nil {
		t.Fatalf("WriteVTT returned error: %v", err)
	}

	want := "WEBVTT\n\n" +
		"00:00:00.000 --> 00:00:04.120\n" +
		"Buenos días a todos.\n\n" +
		"00:00:59.500 --> 00:01:03.000\n" +
		"Pasemos al segundo punto.\n\n" +
		"01:02:00.000 --> 01:02:00.900\n" +
		"Gracias, nos vemos.\n\n"

	if buf.String() != want {
		t.Errorf("got:\n%q\nwant:\n%q", buf.String(), want)
	}
}

func TestWriteSRTWithNoSegmentsWritesNothing(t *testing.T) {
	var buf strings.Builder
	if err := WriteSRT(&buf, &asr.Result{Language: "es"}); err != nil {
		t.Fatalf("WriteSRT returned error: %v", err)
	}
	if buf.String() != "" {
		t.Errorf("got %q, want empty output", buf.String())
	}
}

func TestWriteVTTWithNoSegmentsWritesHeaderOnly(t *testing.T) {
	var buf strings.Builder
	if err := WriteVTT(&buf, &asr.Result{Language: "es"}); err != nil {
		t.Fatalf("WriteVTT returned error: %v", err)
	}
	if buf.String() != "WEBVTT\n\n" {
		t.Errorf("got %q, want %q", buf.String(), "WEBVTT\n\n")
	}
}
