package summary

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/santiagomilos/record-transcriber/internal/asr"
)

func TestParseKindAcceptsKnownKinds(t *testing.T) {
	for input, want := range map[string]Kind{
		"none":     KindNone,
		"":         KindNone,
		"auto":     KindAuto,
		"resumen":  KindResumen,
		"minuta":   KindMinuta,
		"  MINUTA": KindMinuta,
		"Resumen ": KindResumen,
		" Auto":    KindAuto,
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

func TestInstructionDiffersPerKind(t *testing.T) {
	auto, err := instructionFor(KindAuto)
	if err != nil {
		t.Fatalf("instructionFor(KindAuto) returned error: %v", err)
	}
	resumen, err := instructionFor(KindResumen)
	if err != nil {
		t.Fatalf("instructionFor(KindResumen) returned error: %v", err)
	}
	minuta, err := instructionFor(KindMinuta)
	if err != nil {
		t.Fatalf("instructionFor(KindMinuta) returned error: %v", err)
	}
	if auto == resumen || auto == minuta || resumen == minuta {
		t.Error("two kinds share an instruction; all three should differ")
	}
}

// The shared rules are what keep the three kinds honest, so every kind has to
// carry them. This asserts the contract, not the wording: it checks the
// scratchpad step and the tags, which the rest of the package depends on.
func TestEveryKindCarriesTheSharedRules(t *testing.T) {
	for _, kind := range []Kind{KindAuto, KindResumen, KindMinuta} {
		instruction, err := instructionFor(kind)
		if err != nil {
			t.Fatalf("instructionFor(%q) returned error: %v", kind, err)
		}
		for _, want := range []string{"<hechos>", "</hechos>", "<instrucciones>", "</instrucciones>"} {
			if !strings.Contains(instruction, want) {
				t.Errorf("instructionFor(%q) does not contain %q", kind, want)
			}
		}
	}
}

func TestInstructionRejectsKindNone(t *testing.T) {
	if _, err := instructionFor(KindNone); err == nil {
		t.Fatal("expected an error for KindNone, got nil")
	}
}

func TestRenderTranscriptPutsEverySegmentBehindItsStartTime(t *testing.T) {
	r := &asr.Result{
		Language: "es",
		Segments: []asr.Segment{
			{Start: 0, End: 4 * time.Second, Text: "Buenos días."},
			{Start: 4 * time.Second, End: 65 * time.Second, Text: "Vamos con los planes."},
			{Start: 605 * time.Second, End: 610 * time.Second, Text: "Quedamos así."},
		},
	}

	want := "<transcripcion idioma=\"es\">\n" +
		"[00:00] Buenos días.\n" +
		"[00:04] Vamos con los planes.\n" +
		"[10:05] Quedamos así.\n" +
		"</transcripcion>"

	if got := renderTranscript(r); got != want {
		t.Errorf("renderTranscript() =\n%s\nwant\n%s", got, want)
	}
}

// A transcript read back from a plain text file has no timings. Rendering those
// segments as 00:00 would be inventing a timestamp, which the prompt forbids.
func TestRenderTranscriptOmitsTimesForUntimedSegments(t *testing.T) {
	r := &asr.Result{
		Segments: []asr.Segment{
			{Text: "Buenos días."},
			{Text: "Vamos con los planes."},
		},
	}

	want := "<transcripcion>\n" +
		"Buenos días.\n" +
		"Vamos con los planes.\n" +
		"</transcripcion>"

	if got := renderTranscript(r); got != want {
		t.Errorf("renderTranscript() =\n%s\nwant\n%s", got, want)
	}
}

func TestStripScratchpadDropsTheFactList(t *testing.T) {
	out := "<hechos>\n- decision: se aprueba el plan básico\n</hechos>\n\n## Decisiones\n\n- Se aprueba el plan básico."

	got, err := stripScratchpad(out)
	if err != nil {
		t.Fatalf("stripScratchpad returned error: %v", err)
	}
	want := "## Decisiones\n\n- Se aprueba el plan básico."
	if got != want {
		t.Errorf("stripScratchpad() = %q, want %q", got, want)
	}
}

func TestStripScratchpadKeepsOutputThatHasNoScratchpad(t *testing.T) {
	out := "## Decisiones\n\n- Se aprueba el plan básico."

	got, err := stripScratchpad(out)
	if err != nil {
		t.Fatalf("stripScratchpad returned error: %v", err)
	}
	if got != out {
		t.Errorf("stripScratchpad() = %q, want it unchanged", got)
	}
}

func TestStripScratchpadRejectsAnUnclosedScratchpad(t *testing.T) {
	out := "<hechos>\n- decision: se aprueba el plan básico"

	if _, err := stripScratchpad(out); err == nil {
		t.Fatal("expected an error for an unclosed <hechos>, got nil")
	}
}

// Nothing in the package runs the binary, so without this a renamed flag would
// surface only at runtime, after a decode has already been paid for.
func TestClaudeArgsHoldsTheExpectedInvocation(t *testing.T) {
	got := claudeArgs("SYSTEM")
	want := []string{"--print", "--restricted", "--strict-mcp-config", "--system-prompt", "SYSTEM"}

	if len(got) != len(want) {
		t.Fatalf("claudeArgs() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("claudeArgs()[%d] = %q, want %q", i, got[i], want[i])
		}
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
