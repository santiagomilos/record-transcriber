# Adaptive Summaries — Shaping Notes

## Scope

Design the summarization step, which the product declared (record → transcribe → summarize) but
never specified. The summary becomes adaptive: Claude reads the recording, extracts labelled facts,
and the shape of the document follows from which facts exist rather than from a template chosen
before the recording was made.

The recorder, the transcriber and the app's pipeline are untouched. This is prompt design, the
transcript rendering that feeds it, and the plumbing needed to make the result checkable.

## Decisions

**Adaptive shape, fixed vocabulary — not a meeting-type classifier.** The ontology of fact types is
fixed (decision, commitment, open question, risk or blocker, underlying need, context); which
sections appear follows from which facts the transcript yielded. The alternative on the table was a
classifier that picks among N templates — requirements call, standup, interview, voice note. It was
rejected on evidence: no production notetaker documents one (Granola, Fireflies, Otter and Humla
all ship user-picked templates, and Granola's *default* path is described as adapting to a range of
formats), and the published route to adaptivity is different. FRAME/SCOPE (arXiv:2509.15901)
extracts labelled facts and derives the outline from them, reporting hallucination 3→1 and omission
3→1 on a 5-point scale against direct prompting. A classifier also turns a continuous fact
distribution into a brittle discrete choice, where one misclassification silently deforms the whole
output.

Keeping section *names* stable when they do appear is the one thing fixed templates buy, and it
survives here: summaries stay comparable and greppable across sessions without paying the padding
cost of sections that had nothing to fill them.

**One `claude` call with the extraction inside it.** The prompt asks for a labelled fact list in a
`<hechos>` block before any prose, and only the text after `</hechos>` is saved. A two-call pipeline
was the explicit alternative — pass 1 extracting facts to JSON via `--json-schema` (verified to work
against the installed Claude Code and the user's subscription), pass 2 organizing them, with segment
ids carried through so the app could link every bullet to the second of audio it came from. That is
strictly the better product, and it is what the research most supports; it was left out because it
doubles the calls, adds a JSON contract and a second prompt to keep in sync, and this repo's stated
identity is standard library only with no speculative abstractions. The single call captures the
"ground responses in quotes" technique Anthropic documents, which is most of the same benefit.

The cost is accepted and named: the scratchpad spends output tokens on every summary, and a model
that ignores the instruction degrades silently to today's behaviour rather than failing.

**Transcript first, instruction last.** Anthropic's prompting guide puts long inputs at the top and
the query at the end, reporting up to 30% better quality on complex inputs. Today the instruction
arrives via `--system-prompt` and the transcript on stdin, so the instruction lands first. The
system prompt keeps the role only.

**Timestamps are fed but not printed.** Every segment reaches the model as `[mm:ss]`, which gives it
chronology and keeps topics from bleeding together; the rendered summary carries no timestamps by
default. Printing them was considered and rejected as clutter for a document meant to be read.
`format.timestamp` is deliberately not reused: its `HH:MM:SS,mmm` is for subtitles, and millisecond
precision here is tokens spent for nothing.

**Inference is allowed but quarantined.** "What the client actually wants" is the thing the user
asked for and the thing nothing published operationalizes — not in any product schema, paper or
prompt found. Because it is inference rather than transcription, observed facts and the model's
reading live in separate, explicitly labelled sections, and every interpretation bullet names what
was said that supports it.

**`auto` is a new kind, and the fixed ones stay.** It becomes the app's default; `resumen` and
`minuta` remain for forcing a shape. Nothing breaks for a pinned kind. The CLI default stays `none`
— a summary is still opt-in there. Existing installs carry `summaryKind` in UserDefaults already, so
a one-time migration is needed or nobody, this machine included, would ever see the new default.

**The fixed kinds need a closed section list.** Found while verifying, not while planning: sharing
one base between the three kinds leaks the ontology into the fixed ones. `minuta`'s outline named
three sections and said to omit any the transcript gave nothing for, and the first run produced a
fourth — "Preguntas abiertas" — because the shared rules name open questions as a fact type and
nothing forbade a section for them. The outline for `resumen` and `minuta` now closes the list
explicitly. `auto` is the only kind allowed to invent a heading.

**A written transcript becomes a valid input.** `.txt` or `.srt` skips ffmpeg and whisper. Without
it, judging a prompt change means re-decoding 16 minutes of audio per attempt, and "the summary got
better" stays an opinion. `.srt` is included rather than `.txt` alone because it restores the
timings the prompt now feeds.

**The design does not lean on the model thinking harder.** OmniCSEval (arXiv:2606.15974, 28 models
over 1,800 conversations) found reasoning models show no gain, and sometimes a regression, in
faithfulness on summarization. The gains here come from structure — extraction before prose, data
before instruction — not from more reasoning.

## Context

- **Visuals:** none. No mockups exist and the rendered output is Markdown through the app's
  existing renderer.
- **References:** see `references.md`.
- **Product alignment:** this fills in Phase 1 of `agent-os/product/roadmap.md`, which shipped
  summaries as "pipe the transcript into `claude --print`" without specifying what it asks for. It
  stays inside the stated constraints: Go standard library only, no third-party Swift packages, and
  `claude` driven as a subprocess so summaries remain covered by the Claude Code subscription with
  no API key.

  One consequence of that constraint is worth recording: the Messages API features that would help
  most here — the Citations API, which is documented as the right tool for transcripts and would
  return real block indices instead of asking the model to reproduce timecodes, plus structured
  outputs and prompt caching — are not reachable through `claude --print`. The prompt-only
  approximations are what this spec uses.

## Standards Applied

`agent-os/standards/index.yml` is empty, so no standards were pulled in. `standards.md` records the
conventions the existing code holds itself to, which this work continues.
