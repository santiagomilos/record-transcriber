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

Strategy `ask-on-risk`, chain `stacked-to-main` (user delegated the choice). Slices: PR1 T1–T3 + T2b (606e77b..), PR2 T4–T5, PR3 T6. T7 is research, no PR. Push and PR creation wait for the user.

## Tasks

- [x] T1 Surface silent save/read failures (`AppModel.swift`, `LibraryStore.swift`, `SummaryHighlights.swift`)
- [x] T2 Check `claude --restricted` at app start
- [x] T3 Remove duplication in `cmd/transcribe/main.go`
- [x] T2b Summary gate fails open when `claude --help` is unreadable or times out (review finding R4 on T2; regression vs. prior behavior)
- [ ] T4 Remove `app/spike/`
- [ ] T5 Remove `resumen` and `minuta` kinds, keep `requerimientos` untouched
- [ ] T6 Search over past sessions
- [ ] T7 Diarization research (no code)

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

### T2b (SHA_T2B) route: delegated writer
- RED: `make test-swift` failed to compile: `LibraryStore` has no member `dismissLoadProblem` (the `allowsSummaries` expectations for `checking`/`helpUnreadable` were written in the same run and would fail once it compiled).
- GREEN: `make test` ok (114 Swift tests); `go vet ./...` clean.
- Gate now blocks only `claudeMissing` and `restrictedUnsupported`; `helpUnreadable` caption reworded as a warning. `helpOutput` reads on a background queue and the 10s deadline bounds the wait (R3). Library load-problem banner dismisses via `LibraryStore.dismissLoadProblem` (R2). Untested: the timeout path and the banner wiring. ~60 authored lines.

## Next step

Ask the chain strategy (T4 alone exceeds ~400 authored lines), then T4.
