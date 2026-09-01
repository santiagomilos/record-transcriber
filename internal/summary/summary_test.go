package summary

import (
	"context"
	"testing"

	"github.com/santi/record-transcriber/internal/asr"
)

func TestParseKindAcceptsKnownKinds(t *testing.T) {
	for input, want := range map[string]Kind{
		"none":     KindNone,
		"":         KindNone,
		"resumen":  KindResumen,
		"minuta":   KindMinuta,
		"  MINUTA": KindMinuta,
		"Resumen ": KindResumen,
	} {
		got, err := ParseKind(input)
		if err != nil {
			t.Errorf("ParseKind(%q) returned error: %v", input, err)
			continue
		}
		if got != want {
			t.Errorf("ParseKind(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestParseKindRejectsUnknownKind(t *testing.T) {
	if _, err := ParseKind("acta"); err == nil {
		t.Fatal("expected an error for an unknown kind, got nil")
	}
}

func TestPromptDiffersPerKind(t *testing.T) {
	resumen, err := prompt(KindResumen)
	if err != nil {
		t.Fatalf("prompt(KindResumen) returned error: %v", err)
	}
	minuta, err := prompt(KindMinuta)
	if err != nil {
		t.Fatalf("prompt(KindMinuta) returned error: %v", err)
	}
	if resumen == minuta {
		t.Error("resumen and minuta share a prompt; they should not")
	}
}

func TestPromptRejectsKindNone(t *testing.T) {
	if _, err := prompt(KindNone); err == nil {
		t.Fatal("expected an error for KindNone, got nil")
	}
}

func TestGenerateRejectsKindNone(t *testing.T) {
	r := &asr.Result{Segments: []asr.Segment{{Text: "Buenos días."}}}
	if _, err := Generate(context.Background(), r, KindNone); err == nil {
		t.Fatal("expected an error for KindNone, got nil")
	}
}

func TestGenerateRejectsEmptyTranscript(t *testing.T) {
	if _, err := Generate(context.Background(), &asr.Result{}, KindMinuta); err == nil {
		t.Fatal("expected an error for an empty transcript, got nil")
	}
}
