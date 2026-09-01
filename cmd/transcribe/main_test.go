package main

import (
	"slices"
	"testing"
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
