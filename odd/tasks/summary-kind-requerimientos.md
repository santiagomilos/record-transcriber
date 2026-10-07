# Summary kind: requerimientos

## Objective

Offer a `requerimientos` summary kind that turns a transcript into software requirements.

## Why

Requirements gathered in meetings get lost or reworded. A kind built on ISO/IEC/IEEE 29148 quality criteria (atomic, verifiable "shall" statements) and grounded in verbatim quotes gives a reviewable first draft. Plan: `~/.claude/plans/necesito-que-hagas-un-cheeky-hopper.md`.

## Scope

- Go: `KindRequerimientos`, `outlineRequerimientos`, flag help, README.
- Swift: picker list, display name, progress label.
- Out of scope: Gherkin acceptance criteria, a separate system prompt.

## Constraints

- Reuse `instructionOpen`; only the outline is new.
- Markdown limited to `##` and `-` (shared rule), so no tables.

## TDD

Enabled (session config). Runner: `make test` (`go test ./...`, `swift test --package-path app` with Makefile flags).

## Tasks

- [x] T1 Go kind + outline + tests + README (route: delegated writer, 2+ non-trivial files) - commit 2dd7d56
- [x] T2 Swift picker + tests (route: same writer) - commit 5e28c9e

## Acceptance criteria

- `-summary requerimientos` accepted; instruction names five sections and FR-/NFR-/C-/A-/Q- prefixes.
- "Requerimientos" appears in the preferences picker.
- `make test` green.

## Progress

Branch `feat/summary-kind-requerimientos` created.

T1 RED: `go test ./internal/summary` failed to build (`undefined: KindRequerimientos`). GREEN: `go test ./...` ok, `go vet ./...` clean.
T2 RED: `make test-swift` failed 2 tests (name returned "requerimientos", progress label returned "resumen"). GREEN: 103 tests passed.
Final: `make test` green (Go and Swift).
