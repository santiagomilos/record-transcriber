# Project improvements

## Objective

Remove dead weight and close the gaps a daily user notices: lost saves, a silent `claude` breakage, no search, no speakers.

## Why

A project review found silent `try?` saves that drop data, a summary path that breaks at runtime if `claude` renames `--restricted`, overlapping summary kinds, a leftover spike, and no way to find past meetings.

## Scope

- Surface metadata/library save and read failures instead of `try?`.
- Check `claude` (and `--restricted`) when the app starts and tell the user when summaries are unavailable.
- Remove duplicated summary-writing and signal setup in `cmd/transcribe/main.go`.
- Remove `app/spike/` and references to it.
- Remove the `resumen` and `minuta` summary kinds. Keep `none`, `auto` and `requerimientos`; `requerimientos` stays exactly as it is (user decision). Sessions or preferences saved with a removed kind must still open.
- Text search over past sessions' transcripts and summaries in the library window.
- Speaker diarization: research first, implementation after the user reviews the findings.

## Constraints

- Surgical diffs; match existing idioms.
- No new dependency without a justification.
- `requerimientos` prompt, outline and UI are not modified.

## TDD

Enabled (session config). Runner: `make test` (`go test ./...`, `swift test --package-path app` with Makefile flags).

## Delivery

Strategy `ask-on-risk`, chain `stacked-to-main` (user delegated the choice). Slices: PR1 T1–T3 + T2b (606e77b..77f6955), PR2 T4–T5 (ff73c01..bd77730), PR3 T6. T7 is research, no PR. Push and PR creation wait for the user.

## Tasks

- [x] T1 Surface silent save/read failures (`AppModel.swift`, `LibraryStore.swift`, `SummaryHighlights.swift`)
- [x] T2 Check `claude --restricted` at app start
- [x] T3 Remove duplication in `cmd/transcribe/main.go`
- [x] T2b Summary gate fails open when `claude --help` is unreadable or times out (review finding R4 on T2; regression vs. prior behavior)
- [x] T4 Remove `app/spike/`
- [x] T5 Remove `resumen` and `minuta` kinds, keep `requerimientos` untouched
- [x] T6 Search over past sessions
- [x] T7 Diarization research (no code) - findings under Progress

## Acceptance criteria

- A failed metadata save is shown to the user and covered by a test.
- With `claude` missing or lacking `--restricted`, the app says why summaries are unavailable.
- `-summary resumen` and `-summary minuta` are rejected; a session saved with them still loads.
- Library search filters sessions by transcript or summary text, case-insensitively.
- `make test` green after every task.

## Progress

Branch `feat/project-improvements` created from `main` (80c0c8d).

### T1 (606e77b) route: delegated writer
- RED: `make test-swift` failed to compile: `LibraryStore` has no member `loadProblem` (LibraryStoreTests); `AppModel.save` missing (AppModelTests).
- GREEN: `make test-swift` 107 tests passed; `make test` ok; `go vet ./...` clean.
- Kept `try?`: `SummaryHighlights.load` (documented contract: malformed or stale marks are an empty set; save failures already surface in SessionDetailView), `SessionMetadata.load`, `Session` text/creation-date reads (display derivations), `PipelineEvent` line decode, `Opus`/`Components` cleanup and sleeps, `ToolPaths` shell probe.
- Untested: per-entry `resourceValues` failure in `LibraryStore.reload` (cannot be provoked without a race); banner in `LibraryView` (SwiftUI wiring).

### T2 (2207197) route: delegated writer
- RED: `make test-swift` failed to compile: cannot find `SummaryAvailability` in scope.
- GREEN: `make test-swift` 113 tests passed; `make test` ok; `go vet ./...` clean.
- Untested: launch trigger (`MenuBarLabel` task) and the caption in `SessionDetailView` (SwiftUI wiring); real `claude --help` lists `--restricted` on this machine.

### T3 (cbc3421) route: delegated writer
- Pure refactor: `go test ./cmd/...` ok before and after; `make test` ok; `go vet ./...` clean. No new test (helpers carry no logic beyond what existing tests cover).

### Review of T1–T3 (base 80c0c8d, through bc4f493)
- Assessed tier: high. Consent: granted. Four-lens native review: approved and acknowledged (lineage review-c6b1f119e7f51255). Reviewed boundary advances to bc4f493.
- Non-blocking follow-ups worth doing:
  - `SessionDetailView.swift:96`: the summary gate fails closed; a slow or failing `claude --help` disables summaries until a recheck, where before the button worked whenever `claude` existed.
  - `SummaryAvailability.swift:61-66`: `readToEnd` can block past the timeout if a child of `claude` keeps the pipe open.
  - `LibraryView.swift:89-92`: the load-problem `Banner` has a no-op dismiss.

### T2b (77f6955) route: delegated writer
- RED: `make test-swift` failed to compile: `LibraryStore` has no member `dismissLoadProblem` (the `allowsSummaries` expectations for `checking`/`helpUnreadable` were written in the same run and would fail once it compiled).
- GREEN: `make test` ok (114 Swift tests); `go vet ./...` clean.
- Gate now blocks only `claudeMissing` and `restrictedUnsupported`; `helpUnreadable` caption reworded as a warning. `helpOutput` reads on a background queue and the 10s deadline bounds the wait (R3). Library load-problem banner dismisses via `LibraryStore.dismissLoadProblem` (R2). Untested: the timeout path and the banner wiring. ~60 authored lines.

### T4 (ff73c01) route: delegated writer
- Pure deletion: `app/spike/` (build.sh, main.swift) and the README paragraph. `make test` ok (114 Swift tests); `go vet ./...` clean. No Makefile or .gitignore reference existed. Left untouched: historical mentions in `agent-os/product/roadmap.md` and `agent-os/specs/*` (records, not instructions).

### T5 (3e8ef9a Go/README, 6522ec6 Swift) route: delegated writer
- RED (Go): `go test ./internal/summary` failed: `ParseKind("resumen")`, `("minuta")`, `(" Minuta ")` returned nil error. RED (Swift): `make test-swift` failed 3 issues: `summaryKinds` still listed the removed kinds; a stored `resumen` stayed `resumen`.
- GREEN: `make test` ok (115 Swift tests, all Go packages); `go vet ./...` clean.
- `auto` has its own `outlineAuto`; it never reused the removed outlines. Session `meta.json` stores no summary kind, so only the `summaryKind` preference needed a legacy path: any stored value outside `summaryKinds` loads as `auto` and is written back, so the CLI never receives a removed kind (the one-shot `summaryKindMigratedToAuto` key is gone).
- Requerimientos check: `git diff` over summary.go, summary_test.go, Preferences and tests shows no change to `KindRequerimientos`, `outlineRequerimientos`, its display name, or its tests; the only touched lines that mention it are the shared kinds list/error text, the progress-label `case` (now `case "requerimientos": kind`), and tests that previously used `resumen`/`minuta` as sample values. Left: `testdata/README.md` mentions of `minuta-before-redesign.summary.md` (historical comparison fixture).

### T7 diarization research (route: delegated research worker, read-only)
- Recommendation: two steps. First label "me" vs. "others" from the mic and system channels the app captures (needs the recording kept as two tracks or stereo; whisper.cpp `-di` exists but its energy heuristic suffers from mic bleed, so compare per-segment RMS in Go instead). Then diarize the "others" channel with the prebuilt `sherpa-onnx-offline-speaker-diarization` binary (pyannote-segmentation-3.0 + speaker embedding ONNX; v1.13.8 released 2026-09-10, https://github.com/k2-fsa/sherpa-onnx/releases), shelled out from a new `internal/diarize`, assigning each whisper segment the speaker with the largest time overlap.
- Rejected: sherpa Go bindings (cgo + dylibs), tinydiarize (English small.en only), pyannote.audio/whisperX (Python, HF token). FluidAudio (Swift/Core ML; reported 10.6% DER on AMI, https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md, unverified) is the alternative if diarization moves into the app.
- Output shape: `Speaker` on `asr.Segment`; txt `[Speaker 1] text`, srt `Speaker 1: text`, vtt `<v Speaker 1>`; opt-in `-diarize` with graceful fallback.
- Unverified: osx-arm64 archive contents, pyannote conversion license, no Homebrew formula found.
- Open product questions: is "me vs. others" enough; Spanish-first; manual model download acceptable; Go CLI vs. Swift app; speaker rename UI.

### Review of T2b–T5 (base bc4f493 through 6172c01)
- Assessed tier: high. Consent: granted. Four-lens native review: approved and acknowledged (lineage review-de2d1153660c1c5d). Reviewed boundary advances to 6172c01.
- Non-blocking follow-ups: `SummaryAvailability.swift:70-83` the reader thread and `waitUntilExit` can outlive the 10 s deadline when a child of `claude` holds the pipe (accepted tradeoff in T2b); `PreferencesTests.swift:219` the CLI-args assertion is vacuous; `LibraryStoreTests.swift:161-164` the dismiss test precondition is implicit.

### T6 (0d79a7c) route: delegated writer
- RED: `make test-swift` failed to compile: cannot find `SessionSearchIndex` and `LibraryStore` has no member `search`.
- GREEN: `make test` ok (123 Swift tests, 8 new in `SessionSearchTests`: title, transcript, summary, case/accent, no match, blank query, session without files, store sees text after reload); `go vet ./...` clean.
- Design: pure `SessionSearchIndex` (name, display name, transcript, summary folded with case/diacritic-insensitive comparison) caches folded text per session URL, read lazily on the first query; `LibraryStore.reload()` invalidates it. UI is a themed field in the sidebar (not `.searchable`, which clashes with the custom dark panel) plus a "Sin resultados para «X»" state. ~216 authored lines.
- Untested: sidebar wiring in `LibraryView`. Tradeoff: the first search after a reload reads all session files on the main thread (no existing background-load pattern in the store). No match snippet under rows.

### Review of T6 (base 6172c01)
- `gentle-ai review assess --committed-only`: medium, `review_due: false`, `under_budget` (237 lines). No later commit in this feature, so the slice stays unreviewed unless the user asks for one.

## Next step

Open PRs (user decision) and diarization product questions
