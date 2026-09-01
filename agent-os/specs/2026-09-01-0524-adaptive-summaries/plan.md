# Adaptive summaries: give the summarizer a design

## Context

The product defines record → transcribe → summarize, and all three work. What was never
designed is the *summarize* step. `internal/summary/summary.go` holds two hand-written prompts,
`promptResumen` (summary.go:44) and `promptMinuta` (summary.go:59), each naming a fixed set of
sections. `minuta` always asks for "Topics discussed / Decisions made / Action items" whether the
recording is a requirements call, a standup, an interview or a personal voice note.

That is a mismatch with what the summarizer actually is. The summary is written by Claude, which
can read the recording and judge what it is, so the shape should follow the content rather than a
constant chosen before the recording was made. The wanted behaviour is that the summary surfaces
what the client actually wants, what was decided, and what is still open — but only when the
recording contains those things.

A research pass over current practice (Aug–Sep 2026) settled the two questions that were open.

**Do not build a meeting-type classifier.** No production notetaker documents one. Granola,
Fireflies, Otter and Humla all ship user-picked templates; Granola's *default* path, used when
nobody picks, is described as adapting to a range of formats. The route with published evidence is
different: extract labelled facts, then let the outline follow from which facts exist. FRAME/SCOPE
(arXiv:2509.15901) reports hallucination 3→1 and omission 3→1 on a 5-point scale against direct
prompting, on QMSum and FAME — the largest effect in the literature reviewed. A classifier turns a
continuous fact distribution into a brittle discrete choice that can silently deform the whole
output.

**The current prompt has the documented ordering backwards.** Anthropic's prompting guide says to
put long inputs at the top and the query at the end, reporting up to 30% better quality on complex
inputs. Today the instruction arrives in `--system-prompt` and the transcript on stdin — the
instruction lands first.

Two other findings shape the work. Nothing published operationalizes "the underlying need vs. the
stated request", so that section is ours to design and is the reason to quarantine inference from
observation. And OmniCSEval (arXiv:2606.15974, 28 models over 1,800 conversations) found reasoning
models show no gain, sometimes a regression, in faithfulness on summarization — so the design must
not lean on the model thinking harder.

## Decisions

1. **Adaptive shape, fixed vocabulary.** One ontology of fact types is fixed — decision,
   commitment, open question, risk or blocker, underlying need, context. Which sections appear, and
   in what order, follows from which facts the transcript actually yielded. Section names stay
   stable when they do appear, so summaries remain comparable across sessions.
2. **`auto` is a new kind and becomes the app's default.** `resumen` and `minuta` stay for forcing
   a shape. The CLI default stays `none` — a summary remains opt-in there.
3. **One `claude` call, with extraction inside it.** The prompt asks for a labelled fact list in a
   `<hechos>` block first, then the summary written from that list; only the text after `</hechos>`
   is saved. This is the "ground responses in quotes" technique Anthropic documents, and captures
   most of the FRAME benefit without a second subprocess or a JSON contract.
4. **Timestamps are fed, not printed.** The model receives `[mm:ss]` per segment for chronology
   and topic separation; the rendered summary does not carry them by default.
5. **Inference is allowed but quarantined.** Observed facts and the model's reading (underlying
   need, unresolved tension, risk) go in separate, explicitly labelled sections.
6. **A written transcript is a valid input**, so a summary can be regenerated in seconds without
   re-decoding audio. This is what makes "the new prompt is better" checkable rather than an
   opinion.

## Task 1: Save spec documentation

Create `agent-os/specs/2026-09-01-0524-adaptive-summaries/` with `plan.md` (this plan), `shape.md`
(scope, the decisions above with the evidence behind each), `standards.md` (the conventions this
work continues — `agent-os/standards/index.yml` is empty, so none are pulled in) and
`references.md` (the research findings and their sources). No `visuals/`; no mockups exist.

## Task 2: Feed the transcript in the documented shape

`internal/summary/summary.go` builds the stdin payload instead of piping bare prose.

- Add an unexported `renderTranscript(*asr.Result) string` emitting one line per segment as
  `[mm:ss] text`, wrapped in `<transcripcion idioma="es">`. Segments with no timing (a plain-text
  input, Task 5) render without the bracket. Do not reuse `format.timestamp`
  (`internal/format/format.go:52`) — it renders `HH:MM:SS,mmm` for subtitles, and millisecond
  precision here is tokens spent for nothing.
- Order the payload transcript-first, instruction-last, per the long-context guidance.
- `--system-prompt` keeps only the role, not the task.
- Pass `r.Language` as the `idioma` attribute when known, so language selection stops depending on
  the model re-detecting it from the text.

## Task 3: Rewrite the prompts

Compose each prompt from one shared base plus a per-kind outline instruction, so the anti-invention
rules cannot drift between kinds.

The shared base carries:

- The `<hechos>` step: list each fact as a self-contained claim plus the context needed to read it,
  tagged with one ontology label, before writing anything else.
- The fact ontology, fixed.
- Anti-invention rules, tightened past what exists today: never invent a timestamp, only use ones
  present; never invent an owner, write it unassigned; deduplicate decisions and commitments before
  writing; write the explicit null ("no consta") rather than dropping a section silently or padding
  it; mark uncertainty instead of resolving it.
- The ASR rule, narrowed to what the correction literature supports (arXiv:2407.21414): correct
  only what is phonetically plausible as a mishearing, fix errors only, do not rephrase, add or
  remove. Quote verbatim including errors, with any corrected reading in brackets, so a quote stays
  checkable.
- Attribution: no speaker labels exist, so refer to roles ("quien presenta", "el cliente"). An
  invented name is a hallucination even when the content is right — misattribution is its own error
  class in the MESA taxonomy (arXiv:2411.18444).
- The separation rule: observed facts and interpretation never share a section, and every
  interpretation bullet names what was said that supports it.
- No preamble, no closing remark (kept from today).

Per kind: `auto` derives its sections from the facts present; `resumen` renders a short paragraph
plus key points; `minuta` keeps today's three sections. All three inherit the base.

Add `KindAuto` and accept `"auto"` in `ParseKind` (summary.go:31).

## Task 4: Strip the scratchpad

`Generate` (summary.go:98) returns only what follows `</hechos>`. Fail if `<hechos>` opened and
never closed — that output is truncated, and writing a fact dump into `transcript.summary.md` is
worse than failing. Absent the tag entirely, return the output unchanged: the model skipped the
scratchpad, and the summary is still a summary.

Extract the `claude` argument list into a named value so a test can assert it. Today nothing does
(`summary_test.go` never touches the subprocess), so a flag rename surfaces only at runtime.
Verified against the installed Claude Code 2.1.252: `--restricted`, `--strict-mcp-config` and
`--system-prompt` all exist.

## Task 5: Accept a written transcript as input

In `cmd/transcribe/main.go`, when the input is `.txt` or `.srt`, skip `ffmpeg` and `whisper-cli` and
build the `asr.Result` from the file.

`.srt` is included because it restores the timings Task 2 feeds; `.txt` is the degraded path, one
segment and no timestamps. Add the SRT reader beside the writer in `internal/format`, which gives a
write-then-read round trip to test against.

Fail fast on `-summary none` with a transcript input: there is nothing else such a run could do.

## Task 6: Surface `auto` in the app

- `Preferences.summaryKinds` and the default (`Preferences.swift:20,62`) gain `auto`.
- `PreferencesView.swift:83` gains the picker entry.
- A one-time migration moves an existing stored `"minuta"` to `"auto"`, keyed on its own defaults
  key. Without it nobody already running the app — this machine included — ever sees the new
  default, because `summaryKind` is already persisted.
- `TranscribeRunner.swift:26` interpolates the raw kind into `"Generando \(kind)"`, which would read
  "Generando auto". Map the kind to a display name.

No pipeline-event changes: `progress.Summary` (`internal/progress/progress.go:77`) already carries
the kind.

## Task 7: Tests and docs

Go, following the repo's existing style — fixed durations, literal expected strings, no
programmatically built expectations:

- `renderTranscript` against a literal, including the untimed case.
- Scratchpad stripping: tag present, tag absent, tag unclosed.
- Prompt composition: every kind carries the shared rules; the three differ.
- `ParseKind` accepts `auto`.
- SRT round trip, plus a malformed file.
- Flag-list assertion for the `claude` invocation.
- Arg parsing: a transcript input skips decoding; `-summary none` with one is rejected.

Swift: the preferences migration (stored `minuta` moves once and only once, an explicit choice is
left alone), `transcribeArguments` with `auto`, and the display name.

Docs: the `-summary` row and prose in `README.md`, and a line in `agent-os/product/roadmap.md`
recording that the summarizer was designed rather than left implicit.

## Verification

1. `make test` — `go test ./...` and `swift test --package-path app`.
2. `make transcribe`, then regenerate a summary from the transcript already in the repo, which
   takes seconds instead of a full decode:
   `./bin/transcribe -summary auto "2026-08-31 16-53-51.srt"`
3. Diff it against the committed `2026-08-31 16-53-51.summary.md`, which is a real `minuta` of a
   requirements discussion. The check is not that it is longer: the recording contains an
   unresolved argument about how plans relate to quotes, and a deferred decision about
   recommending plans by service count. A good `auto` output surfaces the underlying need and the
   open thread; today's `minuta` flattens both into "Temas tratados".
4. Run the same transcript through `-summary minuta` and confirm the old shape still holds, so the
   change is additive for anyone who pinned a kind.
5. `make app`, record a short clip, and confirm the panel reads "Generando resumen" and the detail
   view renders the new sections through the existing `MarkdownText` renderer — the ontology must
   only produce headings and bullets, which is all that renderer parses
   (`Views/MarkdownText.swift:65`).

## Risks

- **No automatic quality gate.** Summary quality is judged by reading step 3's output. A real eval
  harness (claim-grounded scoring, as in arXiv:2604.21345) is out of scope here; step 2 is what
  makes iterating cheap enough to judge by hand.
- **The scratchpad costs output tokens** on every summary, and a model that ignores the `<hechos>`
  instruction silently falls back to today's behaviour rather than failing.
- **`--system-prompt` replaces Claude Code's default prompt**, and no Claude Code version is pinned
  anywhere in the repo. Task 4's flag assertion catches a rename in `go test`, not at runtime.
