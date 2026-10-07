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
	"time"

	"github.com/santiagomilos/record-transcriber/internal/asr"
)

// BinaryName is the Claude Code executable this package drives. Going through
// the CLI rather than the HTTP API means the summary is covered by the user's
// Claude Code subscription and needs no API key.
const BinaryName = "claude"

// Kind selects what Claude produces from the transcript.
type Kind string

const (
	KindNone Kind = "none"
	// KindAuto lets the shape of the summary follow the recording: the sections
	// that appear are the ones the transcript gave facts for.
	KindAuto Kind = "auto"
	// KindRequerimientos reads the facts as software requirements, following the
	// ISO/IEC/IEEE 29148 criteria of atomic, verifiable statements.
	KindRequerimientos Kind = "requerimientos"
)

// ParseKind validates a --summary flag value.
func ParseKind(s string) (Kind, error) {
	switch Kind(strings.ToLower(strings.TrimSpace(s))) {
	case KindNone, "":
		return KindNone, nil
	case KindAuto:
		return KindAuto, nil
	case KindRequerimientos:
		return KindRequerimientos, nil
	default:
		return "", fmt.Errorf("unknown summary kind %q (want none, auto or requerimientos)", s)
	}
}

// systemPrompt carries the role only. The task lives at the end of the payload
// instead, because Anthropic's prompting guidance puts longform data above the
// instruction that acts on it.
const systemPrompt = `You are a meeting analyst. You read transcripts of recorded conversations and
write accounts of them that someone who missed the recording can act on.`

// instructionOpen holds every rule that does not depend on the kind, so a rule
// cannot drift between the three prompts. Each rule answers a documented failure
// mode; see agent-os/specs/2026-09-01-0524-adaptive-summaries/references.md.
const instructionOpen = `<instrucciones>
Work in two steps.

Step 1. Open a <hechos> block and list every fact the transcript supports. Write each one as a
claim that stands on its own, together with the context needed to read it, and tag it with
exactly one label:

- decision — something settled during the recording
- compromiso — something someone undertook to do
- pregunta — something raised and left unresolved
- riesgo — a risk, an objection or something blocking progress
- necesidad — an underlying need or goal, as distinct from the request that was voiced for it
- contexto — background without which the rest does not read

Step 2. Close the block with </hechos>, then write the account from that list and from nothing
else.

Rules for both steps:

- Record only what the transcript supports. Never invent a detail. Where something is unclear,
  say that it is unclear rather than settling it yourself.
- The transcript has no speaker labels. Refer to people by their role — quien presenta, el
  cliente — and never invent a name. Attributing a line to the wrong person is as wrong as
  inventing the line.
- Never invent an owner or a deadline. Where the transcript does not say who is responsible,
  write that it is unassigned; where no date was given, do not derive one.
- Never write a timestamp that is not in the transcript, and never estimate one.
- The transcript comes from automatic speech recognition, so it contains misheard words. Correct
  only what is plausible as a mishearing of the words you see: fix errors, and do not rephrase,
  add or remove anything. Quote verbatim, putting any corrected reading in brackets, so a quote
  stays checkable against the audio.
- Merge duplicates. A decision circled back to three times is one decision, written as it ended.
- Keep what was said apart from what you conclude. A section of observed fact never carries your
  reading of it, and every line of your reading names the thing that was said that supports it.
- Write a section only where the transcript gives you something for it, and do not pad one out.
  Where a section matters but the transcript is silent, write "no consta" rather than dropping it
  without a word.
- Write in the language of the transcript.
- Use Markdown, limited to ## headings and - bullets. No tables, no nested lists, no block quotes.

`

// instructionClose repeats the no-preamble rule at the very end of the payload,
// which is the last thing the model reads before answering.
const instructionClose = `
Reply with the <hechos> block and then the account itself: no preamble, no closing remark.
</instrucciones>`

// outlineAuto is the whole point of the kind: the document's shape is derived
// from which facts exist, rather than chosen before the recording was made.
const outlineAuto = `Shape for step 2. Choose the sections from the facts you found. A recording that settled things
needs its decisions; one that ended in disagreement needs its open questions; a voice note may
need neither. Open with a short paragraph saying what the recording was, then give the sections
the facts earned, ordered the way the conversation earned them and named for what they hold.

Where the facts support it, add a final section separating what was asked for from what the
underlying goal appears to be, and label it plainly as your reading rather than as something
that was said.`

// The fixed kind has to stay fixed: the shared rules above name fact types
// that are not sections here, and without a closed list the model volunteers a
// section for them.
const outlineRequerimientos = `Shape for step 2. Read the facts as software requirements and write exactly these sections, in
this order, omitting none: functional requirements, non-functional requirements, constraints,
assumptions, and open questions. Add no section beyond those five.

- Write each requirement as one bullet holding one atomic, verifiable statement of the form "the
  system shall ..." or "<role> shall be able to ...". Split anything joined by "and" or "or".
  Number it with its section prefix in order of appearance: FR-1, NFR-1, C-1, A-1, Q-1.
- After the statement, on the same bullet, give: the priority (must, should, could, won't) only
  where the speakers stated it, otherwise say it is not stated; whether it is explicit or
  inferred, and for an inferred one the line it follows from; and a verbatim quote of at most 25
  words as its source.
- Take requirements only from what someone asked for or committed to. A rejected, hypothetical or
  merely floated idea is not a requirement, and nothing comes from what a system of this kind
  usually needs.
- An implementation detail the speakers imposed is a constraint, not a requirement.
- Where a requirement is vague ("fast", "easy"), keep the speaker's word and add an open question
  asking for a measurable target. Where speakers contradict each other, give both versions as one
  open question instead of choosing one.`

// outlineFor returns the kind-specific half of the instruction.
func outlineFor(kind Kind) (string, error) {
	switch kind {
	case KindAuto:
		return outlineAuto, nil
	case KindRequerimientos:
		return outlineRequerimientos, nil
	default:
		return "", fmt.Errorf("summary: no prompt for kind %q", kind)
	}
}

// instructionFor assembles the instruction that follows the transcript.
func instructionFor(kind Kind) (string, error) {
	outline, err := outlineFor(kind)
	if err != nil {
		return "", err
	}
	return instructionOpen + outline + "\n" + instructionClose, nil
}

// clock renders mm:ss. format.timestamp is deliberately not reused: it renders
// HH:MM:SS,mmm for subtitles, and millisecond precision here would be tokens
// spent on a distinction the model has no use for.
func clock(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	secs := int64(d.Seconds())
	return fmt.Sprintf("%02d:%02d", secs/60, secs%60)
}

// renderTranscript lays the transcript out as one line per segment, each behind
// its start time, so the model can tell the order of the conversation and where
// one topic ends. A segment with no timing — everything read back from a plain
// text file — renders as bare text rather than as a false 00:00.
func renderTranscript(r *asr.Result) string {
	var b strings.Builder
	b.WriteString("<transcripcion")
	if lang := strings.TrimSpace(r.Language); lang != "" {
		fmt.Fprintf(&b, " idioma=%q", lang)
	}
	b.WriteString(">\n")
	for _, s := range r.Segments {
		if s.Start > 0 || s.End > 0 {
			fmt.Fprintf(&b, "[%s] ", clock(s.Start))
		}
		b.WriteString(strings.TrimSpace(s.Text))
		b.WriteByte('\n')
	}
	b.WriteString("</transcripcion>")
	return b.String()
}

// stripScratchpad drops the <hechos> working list. It exists to make the model
// extract before it writes, not to be read.
func stripScratchpad(out string) (string, error) {
	const openTag, closeTag = "<hechos>", "</hechos>"
	if i := strings.LastIndex(out, closeTag); i >= 0 {
		return strings.TrimSpace(out[i+len(closeTag):]), nil
	}
	if strings.Contains(out, openTag) {
		return "", errors.New("summary: the model opened <hechos> and never closed it; its answer was cut short")
	}
	// No scratchpad at all means the model skipped step 1. What it wrote is
	// still an account of the recording, so it is worth keeping.
	return strings.TrimSpace(out), nil
}

// claudeArgs is the invocation, named so a test can assert it. Nothing in the
// package executes the binary, so a renamed flag would otherwise surface only at
// runtime, after a decode has already been paid for.
//
// --restricted drops the tools that run code and confines file access, and
// --strict-mcp-config keeps the user's MCP servers out of a job that is pure
// text in, text out.
func claudeArgs(system string) []string {
	return []string{
		"--print",
		"--restricted",
		"--strict-mcp-config",
		"--system-prompt", system,
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
	instruction, err := instructionFor(kind)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(r.Text()) == "" {
		return "", errors.New("summary: transcript is empty")
	}
	if err := CheckAvailable(); err != nil {
		return "", err
	}

	cmd := exec.CommandContext(ctx, BinaryName, claudeArgs(systemPrompt)...)
	cmd.Stdin = strings.NewReader(renderTranscript(r) + "\n\n" + instruction)

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
	return stripScratchpad(out)
}
