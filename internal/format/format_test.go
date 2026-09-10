package format

import (
	"strings"
	"testing"
	"time"

	"github.com/santiagomilos/record-transcriber/internal/asr"
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

func TestReadSRTRecoversEverySegment(t *testing.T) {
	srt := "1\n" +
		"00:00:00,000 --> 00:00:04,120\n" +
		"Buenos días a todos.\n\n" +
		"2\n" +
		"00:00:59,500 --> 00:01:03,000\n" +
		"Pasemos al segundo punto.\n\n" +
		"3\n" +
		"01:02:00,000 --> 01:02:00,900\n" +
		"Gracias, nos vemos.\n\n"

	got, err := ReadSRT(strings.NewReader(srt))
	if err != nil {
		t.Fatalf("ReadSRT returned error: %v", err)
	}

	want := []asr.Segment{
		{Start: 0, End: 4*time.Second + 120*time.Millisecond, Text: "Buenos días a todos."},
		{Start: 59*time.Second + 500*time.Millisecond, End: 63 * time.Second, Text: "Pasemos al segundo punto."},
		{Start: time.Hour + 2*time.Minute, End: time.Hour + 2*time.Minute + 900*time.Millisecond, Text: "Gracias, nos vemos."},
	}

	if len(got.Segments) != len(want) {
		t.Fatalf("read %d segments, want %d", len(got.Segments), len(want))
	}
	for i := range want {
		if got.Segments[i] != want[i] {
			t.Errorf("segment %d = %+v, want %+v", i, got.Segments[i], want[i])
		}
	}
}

// The reader is the inverse of the writer, so what WriteSRT produces has to come
// back unchanged. Language is not carried by the format and does not survive.
func TestReadSRTRoundTripsWhatWriteSRTWrote(t *testing.T) {
	var buf strings.Builder
	if err := WriteSRT(&buf, sample()); err != nil {
		t.Fatalf("WriteSRT returned error: %v", err)
	}

	got, err := ReadSRT(strings.NewReader(buf.String()))
	if err != nil {
		t.Fatalf("ReadSRT returned error: %v", err)
	}

	want := sample().Segments
	if len(got.Segments) != len(want) {
		t.Fatalf("read %d segments, want %d", len(got.Segments), len(want))
	}
	for i := range want {
		if got.Segments[i] != want[i] {
			t.Errorf("segment %d = %+v, want %+v", i, got.Segments[i], want[i])
		}
	}
}

// WriteVTT writes a header and uses a period before the milliseconds; the same
// reader handles it, which is what lets a session be summarized from any of the
// transcripts it wrote.
func TestReadSRTReadsVTTToo(t *testing.T) {
	var buf strings.Builder
	if err := WriteVTT(&buf, sample()); err != nil {
		t.Fatalf("WriteVTT returned error: %v", err)
	}

	got, err := ReadSRT(strings.NewReader(buf.String()))
	if err != nil {
		t.Fatalf("ReadSRT returned error: %v", err)
	}

	want := sample().Segments
	if len(got.Segments) != len(want) {
		t.Fatalf("read %d segments, want %d", len(got.Segments), len(want))
	}
	for i := range want {
		if got.Segments[i] != want[i] {
			t.Errorf("segment %d = %+v, want %+v", i, got.Segments[i], want[i])
		}
	}
}

func TestReadSRTJoinsAMultiLineCue(t *testing.T) {
	srt := "1\n00:00:00,000 --> 00:00:04,000\nBuenos días\na todos.\n\n"

	got, err := ReadSRT(strings.NewReader(srt))
	if err != nil {
		t.Fatalf("ReadSRT returned error: %v", err)
	}
	if len(got.Segments) != 1 {
		t.Fatalf("read %d segments, want 1", len(got.Segments))
	}
	if got.Segments[0].Text != "Buenos días a todos." {
		t.Errorf("text = %q, want %q", got.Segments[0].Text, "Buenos días a todos.")
	}
}

func TestReadSRTRejectsAMalformedTimestamp(t *testing.T) {
	srt := "1\n00:00:00 --> 00:00:04,000\nBuenos días.\n\n"

	if _, err := ReadSRT(strings.NewReader(srt)); err == nil {
		t.Fatal("expected an error for a timestamp with no milliseconds, got nil")
	}
}

func TestReadSRTRejectsAFileWithNoCues(t *testing.T) {
	if _, err := ReadSRT(strings.NewReader("Buenos días a todos.\n")); err == nil {
		t.Fatal("expected an error for a file with no cues, got nil")
	}
}

func TestReadTextRecoversOneSegmentPerLine(t *testing.T) {
	text := "Buenos días a todos.\nPasemos al segundo punto.\nGracias, nos vemos.\n"

	got, err := ReadText(strings.NewReader(text))
	if err != nil {
		t.Fatalf("ReadText returned error: %v", err)
	}

	want := []asr.Segment{
		{Text: "Buenos días a todos."},
		{Text: "Pasemos al segundo punto."},
		{Text: "Gracias, nos vemos."},
	}

	if len(got.Segments) != len(want) {
		t.Fatalf("read %d segments, want %d", len(got.Segments), len(want))
	}
	for i := range want {
		if got.Segments[i] != want[i] {
			t.Errorf("segment %d = %+v, want %+v", i, got.Segments[i], want[i])
		}
	}
}

func TestReadTextRejectsAnEmptyFile(t *testing.T) {
	if _, err := ReadText(strings.NewReader("\n\n")); err == nil {
		t.Fatal("expected an error for a file with no text, got nil")
	}
}
