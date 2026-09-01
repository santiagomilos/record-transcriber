# Standards for the Menu Bar Panel Redesign

`agent-os/standards/index.yml` contains no standards, so none were pulled in. What follows are
the conventions the existing code already holds itself to, which this work continues, plus what
this work adds for view code.

---

## Swift

- **No third-party dependencies.** SwiftUI and Foundation ship with the platform. Markdown
  rendering uses `AttributedString(markdown:)`, not a package.
- **UI state is derived, not duplicated.** The library folder on disk is the source of truth;
  views read from the store that scans it. A view holds `@State` only for what is purely visual —
  hover, the selected tab.
- **Audio teardown is explicit.** Untouched by this work, but any path that ends a recording still
  destroys the process tap and the aggregate device.
- **Comments say what the reader cannot see.** Doc comments describe what a call does for someone
  who will never open the body; inline comments carry a constraint or a rejected alternative, not
  narration. The rationale comments already in `MenuBarView.swift` move with the code they explain.

## Design tokens

- **One file names the raw values.** Colors, spacing, radii and text styles live in `Theme.swift`.
  A view that writes a literal color or an unexplained number is a bug in this spec.
- **Components before copies.** A row that appears in the panel and in the window sidebar is one
  component used twice, not two views that drift.

## Testing

- Boringly explicit: setup, execute, verify, in a straight line. Minimal logic inside a test.
- **Deterministic data:** fixed dates and identifiers, never `now()` or random values. This is why
  the date formatter takes `now` as a parameter — a formatter that reads the clock cannot be
  asserted against a literal.
- **Static expectations:** the expected value is a literal, never built programmatically by the test.
- Beyond the happy path: a missing sidecar, a malformed sidecar, and a session with no files.
- Test names describe the scenario.
- `swift test` and `go test`. No frameworks added.

Views are not unit tested — the repo has no view tests and adding a harness for them is out of
scope. The testable parts of this work are the sidecar round trip, the status derivation, the date
label, and the `transcript` event decoding.

## Documentation

English, plain verbs, claims calibrated to evidence. `README.md` and `agent-os/product/roadmap.md`
describe what the app does, not what it looks like in adjectives.
