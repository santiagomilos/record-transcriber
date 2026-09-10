package main

import (
	"slices"
	"testing"

	"github.com/santiagomilos/record-transcriber/internal/summary"
)

func TestParseFormatsAcceptsAllThreeAndKeepsOrder(t *testing.T) {
	got, err := parseFormats("vtt,txt,srt")
	if err != nil {
		t.Fatalf("parseFormats returned error: %v", err)
	}
	want := []string{"vtt", "txt", "srt"}
	if !slices.Equal(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestParseFormatsNormalizesCaseAndSpacing(t *testing.T) {
	got, err := parseFormats(" TXT , Srt ")
	if err != nil {
		t.Fatalf("parseFormats returned error: %v", err)
	}
	want := []string{"txt", "srt"}
	if !slices.Equal(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestParseFormatsDropsDuplicates(t *testing.T) {
	got, err := parseFormats("srt,srt,txt")
	if err != nil {
		t.Fatalf("parseFormats returned error: %v", err)
	}
	want := []string{"srt", "txt"}
	if !slices.Equal(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestParseFormatsRejectsUnknownFormat(t *testing.T) {
	if _, err := parseFormats("txt,docx"); err == nil {
		t.Fatal("expected an error for an unknown format, got nil")
	}
}

func TestParseFormatsRejectsEmptyList(t *testing.T) {
	if _, err := parseFormats(" , "); err == nil {
		t.Fatal("expected an error for an empty format list, got nil")
	}
}

func TestOutputBaseForStripsExtension(t *testing.T) {
	if got := outputBaseFor("/Users/santi/reunion.mp4"); got != "/Users/santi/reunion" {
		t.Errorf("got %q, want %q", got, "/Users/santi/reunion")
	}
}

func TestOutputBaseForKeepsDotsInDirectories(t *testing.T) {
	got := outputBaseFor("/Users/santi/notas.v2/reunion.m4a")
	want := "/Users/santi/notas.v2/reunion"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestOutputBaseForLeavesExtensionlessPathAlone(t *testing.T) {
	if got := outputBaseFor("/Users/santi/reunion"); got != "/Users/santi/reunion" {
		t.Errorf("got %q, want %q", got, "/Users/santi/reunion")
	}
}

func TestParseArgsRequiresExactlyOneInput(t *testing.T) {
	if _, err := parseArgs([]string{}); err == nil {
		t.Fatal("expected an error with no input file, got nil")
	}
	if _, err := parseArgs([]string{"a.mp4", "b.mp4"}); err == nil {
		t.Fatal("expected an error with two input files, got nil")
	}
}

func TestParseArgsDerivesOutputBaseFromInput(t *testing.T) {
	cfg, err := parseArgs([]string{"/tmp/reunion.mp4"})
	if err != nil {
		t.Fatalf("parseArgs returned error: %v", err)
	}
	if cfg.outputBase != "/tmp/reunion" {
		t.Errorf("outputBase = %q, want %q", cfg.outputBase, "/tmp/reunion")
	}
}

func TestParseArgsOutputFlagWinsOverDerivedBase(t *testing.T) {
	cfg, err := parseArgs([]string{"-o", "/tmp/salida", "/tmp/reunion.mp4"})
	if err != nil {
		t.Fatalf("parseArgs returned error: %v", err)
	}
	if cfg.outputBase != "/tmp/salida" {
		t.Errorf("outputBase = %q, want %q", cfg.outputBase, "/tmp/salida")
	}
}

func TestParseArgsRejectsUnknownSummaryKind(t *testing.T) {
	if _, err := parseArgs([]string{"-summary", "acta", "/tmp/reunion.mp4"}); err == nil {
		t.Fatal("expected an error for an unknown summary kind, got nil")
	}
}

func TestParseArgsMarksATranscriptInput(t *testing.T) {
	for _, input := range []string{"reunion.srt", "reunion.txt", "reunion.vtt", "reunion.SRT"} {
		cfg, err := parseArgs([]string{"-summary", "auto", input})
		if err != nil {
			t.Errorf("parseArgs(%q) returned error: %v", input, err)
			continue
		}
		if !cfg.fromTranscript {
			t.Errorf("parseArgs(%q) did not mark the input as a transcript", input)
		}
	}
}

func TestParseArgsTreatsMediaAsSomethingToDecode(t *testing.T) {
	for _, input := range []string{"reunion.mp4", "reunion.m4a", "reunion.opus"} {
		cfg, err := parseArgs([]string{"-summary", "auto", input})
		if err != nil {
			t.Errorf("parseArgs(%q) returned error: %v", input, err)
			continue
		}
		if cfg.fromTranscript {
			t.Errorf("parseArgs(%q) marked media as a transcript", input)
		}
	}
}

// A transcript input produces nothing but the summary, so asking for no summary
// asks for no work at all.
func TestParseArgsRejectsATranscriptInputWithNoSummary(t *testing.T) {
	if _, err := parseArgs([]string{"reunion.srt"}); err == nil {
		t.Fatal("expected an error for a transcript input with -summary none, got nil")
	}
}

func TestParseArgsAcceptsAutoAsASummaryKind(t *testing.T) {
	cfg, err := parseArgs([]string{"-summary", "auto", "reunion.mp4"})
	if err != nil {
		t.Fatalf("parseArgs returned error: %v", err)
	}
	if cfg.summaryKind != summary.KindAuto {
		t.Errorf("summaryKind = %q, want %q", cfg.summaryKind, summary.KindAuto)
	}
}

func TestParseArgsDerivesSummaryPathFromATranscriptInput(t *testing.T) {
	cfg, err := parseArgs([]string{"-summary", "auto", "/tmp/sesion/transcript.srt"})
	if err != nil {
		t.Fatalf("parseArgs returned error: %v", err)
	}
	if cfg.outputBase != "/tmp/sesion/transcript" {
		t.Errorf("outputBase = %q, want %q", cfg.outputBase, "/tmp/sesion/transcript")
	}
}
