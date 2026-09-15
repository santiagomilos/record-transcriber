# References for Summary Text Size and Highlights

No external references or visuals. Everything this work builds on is in the app.

## Code in this repo

### The summary renderer

- **Location:** `app/Sources/RecordTranscriber/Views/MarkdownText.swift`
- **Relevance:** `Block.parse` splits `claude --print` output into headings, bullets and paragraphs
  and is kept as is. The SwiftUI view around it is what gets replaced, because its `Text` views
  cannot report a selection.
- **Key patterns to keep:** heading sizes 17 / 14 / 12.5 over a 12 pt body; inline markup parsed
  with `inlineOnlyPreservingWhitespace`, falling back to the raw line when parsing fails; ordered
  items keep their own number.

### The sidecar idiom

- **Location:** `app/Sources/RecordTranscriber/Library/SessionMetadata.swift`
- **Relevance:** `meta.json` is the precedent for per-session state beside the pipeline's files.
- **Key patterns to borrow:** `load(from:)` returns nil for a missing or malformed file;
  `save(to:)` writes pretty-printed, sorted keys, which is what lets tests assert the JSON as a
  literal (`SessionMetadataTests.swift`).

### Audio resolution in a session folder

- **Location:** `app/Sources/RecordTranscriber/Library/Session.swift`, `audioFile(among:)`
- **Relevance:** any unknown file in an import's folder is a candidate recording unless its name
  starts with `transcript.`, is `meta.json`, is hidden or ends in `.part`. This is why the
  highlights file is `transcript.summary.highlights.json`.

### Persisted preferences

- **Location:** `app/Sources/RecordTranscriber/Preferences/Preferences.swift`
- **Relevance:** `Key` constants, `didSet` writes to the injected `UserDefaults`, and defaults read in
  `init`. `PreferencesTests.swift` tests a relaunch by building a second instance on the same suite.

### Detail view and its controls

- **Location:** `app/Sources/RecordTranscriber/Views/SessionDetailView.swift`,
  `app/Sources/RecordTranscriber/Views/Components.swift`
- **Relevance:** `tabs(copyable:)` already places a tab-specific control (`CopyButton`) in
  `TabStrip`'s trailing slot; the size buttons join it there as `IconButton`s, which carry the app's
  own tooltip. `model.failure` is how the view reports a file error.
