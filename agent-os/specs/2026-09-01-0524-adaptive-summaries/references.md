# References for Adaptive Summaries

Two kinds of reference matter here. The code this work extends is small and local. The research
that decided the design is external, and is recorded in more detail than usual because the
decisions are not obvious from reading the diff.

## Code in this repo

### The summarizer as it stands

- **Location:** `internal/summary/summary.go`
- **Relevance:** the whole feature lives in 139 lines. `promptResumen` (line 44) and `promptMinuta`
  (line 59) are the two fixed prompts being replaced; `Generate` (line 98) is the single call site.
- **Key patterns to keep:** `CheckAvailable` is called before transcription from
  `cmd/transcribe/main.go:76`, so a missing `claude` fails in a second rather than after a long
  decode. `--restricted` and `--strict-mcp-config` keep a text-in/text-out job away from tools and
  the user's MCP servers. Empty stdout is an error, and stderr is folded into the error message.
- **What it does not have:** no test touches the subprocess, so the flag list and the prompt text
  are unverified by `go test`.

### The transcript the summarizer consumes

- **Location:** `internal/asr/transcriber.go`
- **Relevance:** `Segment` carries `Start` and `End`, but `Result.Text()` (line 25) joins segments
  into flat prose, so every timing is discarded before Claude sees the transcript. That is the gap
  the new rendering closes.

### Subtitle rendering

- **Location:** `internal/format/format.go`
- **Relevance:** `WriteSRT` is the shape the new SRT reader round-trips against. Its unexported
  `timestamp` helper (line 52) renders `HH:MM:SS,mmm` and is deliberately *not* reused for the
  prompt.

### The app's preference plumbing

- **Location:** `app/Sources/RecordTranscriber/Preferences/Preferences.swift`
- **Relevance:** `summaryKinds` (line 20), the stored default (line 62) and `transcribeArguments`
  (line 69) are the three places `auto` has to appear. The doc comment on `Key` already states that
  defaults keys are stable and renaming one silently resets the preference — which is exactly why
  the new default needs a migration rather than a renamed key.

### The Markdown renderer that displays the result

- **Location:** `app/Sources/RecordTranscriber/Views/MarkdownText.swift`
- **Relevance:** hand-written, and it parses only headings (`#`..`###`), bullets and paragraphs
  (`Block.parse`, line 65). It is the constraint on the output format: the prompt must not produce
  tables, block quotes or nested lists, because nothing would render them.

### A real output to judge against

- **Location:** `testdata/reunion-planes-2026-08-31/` — `transcript.srt` and
  `minuta-before-redesign.summary.md`
- **Relevance:** a genuine `minuta` of a 16-minute Spanish requirements discussion, kept beside the
  transcript it came from. It is the fixture the new prompt is compared against, and it shows the
  failure being fixed: an unresolved argument about how plans relate to quotes, and a deferred
  decision about recommending plans by service count, both flattened into "Temas tratados".
  The fixture is untracked, as everything carrying meeting content is; `testdata/README.md`
  describes it.

### Prior specs, for document shape

- **Location:** `agent-os/specs/2026-09-01-0419-menu-bar-panel-redesign/`
- **Relevance:** the `shape.md` / `standards.md` / `references.md` convention this spec follows,
  including recording the rejected alternative next to each decision.

## Research (Aug–Sep 2026)

Recorded because the design rests on it. Where a claim is inference rather than something a source
states, it is marked.

### The technique the prompt is built on

- **Anthropic — prompting best practices**
  (`platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices`).
  Two rules drive the payload layout. Verbatim: *"Put longform data at the top: Place your long
  documents and inputs near the top of your prompt, above your query, instructions, and examples."*
  with the note that *"Queries at the end can improve response quality by up to 30 percent in
  tests, especially with complex, multidocument inputs."* And on grounding: *"For long document
  tasks, ask Claude to quote relevant parts of the documents first before carrying out its task."*
  The XML-tag guidance (`<document>`, `<document_content>`) is from the same page.
- **Anthropic — legal summarization use-case guide**
  (`platform.claude.com/docs/en/about-claude/use-case-guides/legal-summarization`). The source of
  three transferable moves: an explicit list of details to extract (*"There is no single correct
  summary for any given document. Without clear direction, it can be difficult for Claude to
  determine which details to include."*), XML-headed sections, and the explicit null — *"If any
  information is not explicitly stated in the document, note it as 'Not specified'. Do not
  preamble."* The repo's "no consta" is that rule.

### Why the shape is adaptive and there is no classifier

- **FRAME / SCOPE — Kirstein, Kumar, Ruas, Gipp (arXiv:2509.15901).** The load-bearing paper.
  Reframes meeting summarization as semantic enrichment over four stages: identify facts as
  statement–context tuples, label each with a function (Decision / Action Item / Insight / Context)
  and a relevance score, build an outline from the rated facts, then write from the outline.
  Reports hallucination 3→1 and 4→1, omission 3→1 and 4→1, and irrelevance 2→1 and 3→1 on the MESA
  5-point scale, on QMSum and FAME. The architectural claim taken from it: the summary's shape
  follows the extracted facts, not a template and not a classifier.
- **Granola — templates and the default path**
  (`docs.granola.ai/help-center/taking-notes/customise-notes-with-templates`,
  `granola.ai/blog/meeting-note-templates-by-type`). Templates are user-picked; the no-template
  default *"adapts to a range of formats"*. Their own research-template post warns that *"If rigid
  template adherence pulls you back to prepared structure, you lose the best data in the
  interview."*
- **Fireflies — summary schema** (`docs.fireflies.ai/schema/summary`). The most concrete published
  production contract: `action_items`, `outline` ("with timestamps"), `overview`, `gist`,
  `topics_discussed`, `meeting_type`, and `transcript_chapters` built on *"an LLM-condensed
  transcript … helpful for downstream applications"* — production convergence on keeping an
  intermediate representation. Note that `meeting_type` is stored, but nothing in their docs says
  it drives the summary's shape.
- **Absence, stated plainly:** no commercial notetaker's real system prompt is public, and no
  product documents a classify-then-summarize pass. Both were searched for specifically. The
  reading that products use fixed templates for CRM-comparability rather than for quality is
  inference, not a sourced claim.

### The anti-invention rules

- **Microsoft Community Hub — Copilot prompt for Teams meeting analysis, v1.5** (2026-01-14). The
  most explicit published example of the discipline. Rules borrowed nearly verbatim: *"NEVER invent
  details. If unclear, mark as 'Unclear' or 'TBD.'"*, *"Only include timestamps if explicitly
  present in transcript; never estimate or invent them"*, and *"Deduplicate action items,
  decisions, and risks before final output"*. Its decision status vocabulary
  (Confirmed / Tentative / Disputed) is the model for marking uncertainty rather than resolving it.
- **MESA — Kirstein et al. (arXiv:2411.18444).** The error taxonomy the rules target: hallucination,
  omission, irrelevance, repetition, incoherence, structural flaws, and **coreference problems
  (unresolved references, misattributions, missing mentions)**. The last one is why an invented
  speaker name counts as a hallucination even when the content is right — the operative failure mode
  for a transcript with no diarization.
- **ASR error correction (arXiv:2405.15216, arXiv:2407.21414).** The narrowed correction rule.
  The first contributes the containment — *"Correct any transcription errors in the following text.
  Only fix errors—do not add, remove, or rephrase content."*; the second contributes the phonetic
  anchor, finding that steering toward acoustically plausible corrections works better than
  toward semantically convenient ones. Today's *"use what was meant"* has neither.

### What was checked and deliberately not used

- **Citations API** (`platform.claude.com/docs/en/build-with-claude/citations`). Documents custom
  content blocks as the right granularity for *"Lists, transcripts, special formatting"*, returning
  block indices that map straight onto segment timings — real citations the model cannot
  hallucinate. Unreachable through `claude --print`, and it cannot be combined with structured
  outputs. This is the strongest argument on file for someday adding a Messages API path.
- **Chunking and map-reduce.** Anthropic's meta-summarization recipe notes it *"often captures
  additional important details … that were missed in the earlier single-summary approach"* even when
  the document fits. Not adopted: measured on this repo's own sample, 16 minutes of speech is 2,045
  words, so a four-hour recording is roughly 40k tokens. Long-context structure matters from ~20k
  tokens (about 1.5 hours), which is the point to revisit this; context capacity never binds.
  `meetily` (`github.com/Zackriya-Solutions/meetily`) is the negative example — fixed 5,000-char
  chunks with no reduce step, so cross-chunk deduplication and decision-reversal tracking never
  happen.
- **Extended thinking.** OmniCSEval (arXiv:2606.15974, 2026-07-31; 28 models, 1,800 conversations,
  including MeetingBank and QMSum) found reasoning models show *"no gain, or even regress, in
  faithfulness"*, and that *"Models that think longer do not necessarily achieve greater
  performance, particularly in completeness and faithfulness."* Their protocol was a bare
  zero-shot "Summarize the above conversation", which limits how far the negative result transfers
  to a structured prompt — but it is enough reason not to build on more reasoning.
- **An evaluation harness.** The vocabulary worth stealing if one is ever built, from OmniCSEval:
  completeness as recall of aligned key facts, conciseness as density of fact-matched sentences,
  faithfulness as precision of supported facts — all scored against an extracted fact set rather
  than a reference string. A cross-domain pipeline paper (arXiv:2604.21345, 114 meetings, 340
  meeting-model pairs) found model choice separates on coverage and completeness, not accuracy.
  Out of scope here; cheap regeneration from a written transcript is what makes hand-judging
  practical instead.

### The gap this fills

Nothing found — no product schema, template, paper or published prompt — operationalizes "the
underlying need versus the stated request". The nearest documented practice is BANT and "pain
points" fields in sales templates, which are neither summarization prompts nor inference-aware.
That the safe construction is a separately labelled inference layer over the fact list is this
spec's own reasoning, not a sourced recommendation.
