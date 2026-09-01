// Package summary turns a transcript into a summary or a meeting minute by
// driving the Claude Code CLI as a subprocess.
package summary

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/santi/record-transcriber/internal/asr"
)

// BinaryName is the Claude Code executable this package drives. Going through
// the CLI rather than the HTTP API means the summary is covered by the user's
// Claude Code subscription and needs no API key.
const BinaryName = "claude"

// Kind selects what Claude produces from the transcript.
type Kind string

const (
	KindNone    Kind = "none"
	KindResumen Kind = "resumen"
	KindMinuta  Kind = "minuta"
)

// ParseKind validates a --summary flag value.
func ParseKind(s string) (Kind, error) {
	switch Kind(strings.ToLower(strings.TrimSpace(s))) {
	case KindNone, "":
		return KindNone, nil
	case KindResumen:
		return KindResumen, nil
	case KindMinuta:
		return KindMinuta, nil
	default:
		return "", fmt.Errorf("unknown summary kind %q (want none, resumen or minuta)", s)
	}
}

const promptResumen = `You summarize meeting and voice-note transcripts.

Write the summary in the same language as the transcript.

Produce:
- A short paragraph saying what the recording was about.
- The key points, as a list.

The transcript comes from automatic speech recognition, so it has no speaker
labels and may contain misheard words. Where a word is clearly a recognition
error, use what was meant. Do not invent anything the transcript does not say,
and do not speculate about who was speaking.

Reply with the summary itself and nothing else: no preamble, no closing remark.`

const promptMinuta = `You turn meeting transcripts into structured minutes.

Write the minutes in the same language as the transcript.

Produce these sections, omitting any section the transcript gives you nothing for:
- Topics discussed
- Decisions made
- Action items, each with its owner and its deadline when one was stated

The transcript comes from automatic speech recognition, so it has no speaker
labels and may contain misheard words. Where a word is clearly a recognition
error, use what was meant. Only record a decision or an action item that was
actually stated. Never invent an owner: if the transcript does not say who is
responsible, write that it is unassigned.

Reply with the minutes themselves and nothing else: no preamble, no closing remark.`

// prompt returns the system prompt for a kind.
func prompt(kind Kind) (string, error) {
	switch kind {
	case KindResumen:
		return promptResumen, nil
	case KindMinuta:
		return promptMinuta, nil
	default:
		return "", fmt.Errorf("summary: no prompt for kind %q", kind)
	}
}

// CheckAvailable reports whether a summary can be produced. Callers use it to
// fail before transcribing rather than after.
func CheckAvailable() error {
	if _, err := exec.LookPath(BinaryName); err != nil {
		return fmt.Errorf("%s is not on your PATH — install Claude Code, or drop --summary", BinaryName)
	}
	return nil
}

// Generate sends the transcript to Claude and returns the rendered markdown.
func Generate(ctx context.Context, r *asr.Result, kind Kind) (string, error) {
	system, err := prompt(kind)
	if err != nil {
		return "", err
	}
	if err := CheckAvailable(); err != nil {
		return "", err
	}

	transcript := r.Text()
	if transcript == "" {
		return "", errors.New("summary: transcript is empty")
	}

	// --restricted drops the tools that run code and confines file access, and
	// --strict-mcp-config keeps the user's MCP servers out of a job that is
	// pure text in, text out.
	cmd := exec.CommandContext(ctx, BinaryName,
		"--print",
		"--restricted",
		"--strict-mcp-config",
		"--system-prompt", system,
	)
	cmd.Stdin = strings.NewReader(transcript)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return "", fmt.Errorf("summary: %s failed: %w: %s", BinaryName, err, msg)
		}
		return "", fmt.Errorf("summary: %s failed: %w", BinaryName, err)
	}

	out := strings.TrimSpace(stdout.String())
	if out == "" {
		return "", fmt.Errorf("summary: %s returned no text", BinaryName)
	}
	return out, nil
}
