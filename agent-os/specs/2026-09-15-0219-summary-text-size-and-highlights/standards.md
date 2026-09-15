# Standards for Summary Text Size and Highlights

`agent-os/standards/index.yml` contains no standards, so none were pulled in. What follows are the
conventions the existing app code already holds itself to, as they apply to this work.

---

## SwiftUI and AppKit

- **Theme is the only place that names a color or a metric.** The four highlight colors, the
  selection color and the font size range's visual defaults are tokens in `Views/Theme.swift`; the
  text view reads them rather than writing literals.
- **One fixed dark palette.** The panel does not follow the system appearance, so an AppKit view
  must set its own text, background and selection colors instead of inheriting system ones.
- **No third-party packages.** AppKit and CryptoKit ship with macOS.
- **Spanish in the UI, English in the code.** Menu items (`Resaltar`, `Quitar resaltado`, color
  names) and tooltips are Spanish; identifiers, comments and commits are English.
- **Comments say what the reader cannot see.** Why the summary is an `NSTextView`, why the file name
  starts with `transcript.`, why marks store their text: each lives next to the code it constrains.

## Persistence

- **The session folder is the source of truth.** No database; anything a session owns sits in its
  folder so copying the folder copies it.
- **A missing or malformed sidecar is not an error.** It loads as nothing, the way
  `SessionMetadata.load` treats `meta.json`. Failing to write one is an error and reaches the user.
- **UserDefaults keys are stable.** A renamed key silently resets the preference for everyone who
  has it set.

## Testing

- **swift-testing, run through `make test`.** One file per unit under
  `app/Tests/RecordTranscriberTests/`.
- **Straight-line tests with hardcoded expectations.** Expected JSON and rendered strings are
  literals; fixed ranges and colors, no random data. Temporary folders and isolated defaults suites
  per test, as the existing tests do.
- **Beyond the happy path.** Overlapping and adjacent marks, removal over nothing, a changed
  summary, a stale mark, a malformed file, both ends of the size range.

## Git

- **Conventional Commits, atomic.** Spec docs, the highlights model, the size preference, the
  renderer refactor, the view and the roadmap note are separate commits with their own type.
