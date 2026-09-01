# Standards for Adaptive Summaries

`agent-os/standards/index.yml` contains no standards, so none were pulled in. What follows are the
conventions the existing code already holds itself to, which this work continues, plus what this
work adds for prompt code.

---

## Go

- **Standard library only.** The module has no dependencies and this work adds none. Parsing SRT is
  `bufio` and `strings`; building the prompt payload is `strings.Builder`.
- **Every capability the tool does not implement comes from a binary it shells out to.** That is why
  the dependency list is empty, and why summaries go through `claude --print` rather than an HTTP
  client.
- **Fail fast, at the top.** `CheckAvailable` runs before transcription so a missing `claude` costs
  a second, not a full decode. The new input path follows the same rule: a transcript input with
  `-summary none` is rejected during argument parsing, not after the file is read.
- **Specific errors, never swallowed.** Errors wrap with `%w` and name the file or the binary that
  failed. A truncated model response is an error, not a partial file written to disk.
- **Return early.** No nested conditionals where a guard clause reads the same.

## Prompts

Prompt text is code: it is version-controlled, reviewed, and tested. The rules it must keep:

- **One base, composed per kind.** The anti-invention rules exist once. A rule that has to be
  repeated in three prompts will drift between them, which is the defect this spec exists to fix.
- **Data first, instruction last.** The transcript goes at the top of the payload and the task at
  the bottom. The system prompt carries the role, not the task.
- **Structure with XML tags, output Markdown.** Tags delimit the input and the scratchpad; the
  saved output is Markdown limited to headings and bullets, because that is all
  `MarkdownText.swift` parses.
- **Every instruction earns its place.** A rule goes in because a named failure mode motivates it,
  and the motivation is recorded in `references.md` rather than narrated in the prompt.
- **Prompts are English; the output follows the transcript.** Repo content is English by
  convention. The section names the model emits are in the transcript's language, which for this
  product is usually Spanish.

## Comments

- Doc comments describe what a call does for someone who will never open the body.
- Inline comments carry a constraint, a coupling or a rejected alternative — not narration. The
  reason `format.timestamp` is not reused, and the reason the scratchpad is stripped rather than
  suppressed, both belong in the code.
- No commented-out code.

## Testing

- Boringly explicit: setup, execute, verify, in a straight line. Minimal logic inside a test.
- **Deterministic data:** fixed durations and literal transcript text. Never `now()`, never random.
- **Static expectations:** the expected payload is a string literal, never assembled by the test
  using the same helper it is checking.
- **Beyond the happy path:** a scratchpad that is absent, and one that is opened and never closed;
  a segment with no timing; a malformed SRT; a transcript input with `-summary none`.
- **Assert the contract, not the wording.** Tests check that every kind carries the shared rules and
  that the three differ — not that a particular sentence is present, which would make every prompt
  edit a test edit.
- The `claude` subprocess is still not executed by any test. What becomes testable is the argument
  list, which today is unverified and would surface a flag rename only at runtime.
- `go test ./...` and `swift test`. No frameworks added.

## Swift

- **No third-party packages.** Foundation and SwiftUI only.
- **Preferences keys are stable.** Renaming one silently resets that preference for anyone who has
  it set, which is why a changed default ships as an explicit one-time migration rather than a new
  key.
- **The mapping from preference to CLI flag lives in one place** (`transcribeArguments`) so it can
  be tested without running anything.
- **Views are not unit tested.** The repo has no view tests and this work adds no harness for them.

## Documentation

English, plain verbs, claims calibrated to evidence. `README.md` documents the flag values and what
the summary contains; it does not describe the prompt line by line, which would go stale on the
first edit.
