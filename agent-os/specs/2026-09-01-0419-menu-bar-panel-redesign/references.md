# References for the Menu Bar Panel Redesign

## Visual reference

### JetBrains Toolbox menu bar panel

- **Location:** `visuals/toolbox-reference.png`
- **Relevance:** the target shape for the panel.
- **Key patterns:** a header carrying the product mark, its name and a small row of icon
  actions; content grouped into cards with a quiet border rather than separated by dividers;
  section headers inside the cards; list items that carry their own secondary line of metadata.

## Similar implementations in this repo

### The existing menu bar panel

- **Location:** `app/Sources/RecordTranscriber/Views/MenuBarView.swift`
- **Relevance:** what is being replaced, and what has to survive the replacement.
- **Key patterns to keep:** the failure banner is repeated here rather than only in the window
  because the window is usually closed while recording (comment at lines 11-13); `LevelMeter`
  shows the two sources separately because the common failure is capturing only your own voice,
  which a single mixed bar hides (lines 80-82); `displayLevel` maps peaks onto a decibel curve
  because a linear bar spends most of its length on levels nobody records at.

### Session and LibraryStore

- **Location:** `app/Sources/RecordTranscriber/Library/Session.swift`,
  `app/Sources/RecordTranscriber/Library/LibraryStore.swift`
- **Relevance:** where the new metadata and status derivation belong.
- **Key patterns:** the folder on disk is the source of truth and `reload` rebuilds the list from
  it, so nothing is cached that the Finder can invalidate; a missing library folder is an empty
  library, not an error — the same posture the sidecar reader takes for a missing `meta.json`.

### TranscribeRunner and PipelineEvent

- **Location:** `app/Sources/RecordTranscriber/Pipeline/TranscribeRunner.swift`,
  `app/Sources/RecordTranscriber/Pipeline/PipelineEvent.swift`
- **Relevance:** the source of the language and segment count the rows will show.
- **Key patterns:** `Phase` already exposes a Spanish `label` and an optional `fraction` that
  tells a progress bar to stay indeterminate — the redesigned panel renders those rather than
  inventing its own vocabulary. `apply` folds one event into published state and currently drops
  the `transcript` event; that is the single place to change.

### The Phase 2 spec

- **Location:** `agent-os/specs/2026-09-01-0255-macos-recording-app/`
- **Relevance:** the spec that built the app being redesigned.
- **Key patterns:** its Task 7 specced a Preferences item in the menu that was never
  implemented, and its Task 8 specced sidebar rows "each with date, duration and status" and a
  detail pane with rendered markdown — all of which this spec finally delivers. Its
  `standards.md` is the model for this one.
