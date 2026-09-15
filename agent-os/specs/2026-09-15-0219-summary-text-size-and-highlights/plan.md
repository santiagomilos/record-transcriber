# Summary reading: adjustable text size and saved highlights

## Context

The summary tab in `SessionDetailView` renders `transcript.summary.md` at a fixed 12 pt through
`MarkdownText`, a stack of SwiftUI `Text` views. The owner reads summaries in the app and wants
two things: make the text larger or smaller to taste, and mark passages with a highlighter whose
marks survive closing the app.

Decisions made during shaping (`/agent-os:shape-spec`):

- **Highlighter with several colors** (yellow, green, pink, blue), not a literal underline.
- Applied and removed from the **context menu** on a selection: `Resaltar ▸ <color>` and
  `Quitar resaltado`. No extra toolbar.
- Saved in a **separate file in the session folder**; `transcript.summary.md` stays untouched.
- **A regenerated summary starts clean**: highlights from the previous text are discarded.
- Text size is **global and applies to the summary only**: A− / A+ next to the tabs plus ⌘+ / ⌘−,
  remembered across sessions and launches.
- No visuals, no external references. `agent-os/standards/index.yml` is empty, so `standards.md`
  restates the repo's own conventions, as previous specs do.

### Constraint that shapes the design

The app targets macOS 14.4. On that version SwiftUI's `Text` with `.textSelection(.enabled)` never
exposes the selected range, and the attributed `TextEditor` with a selection binding only exists
from macOS 26. Highlighting needs the selection, so the summary moves to an `NSTextView` wrapped
in `NSViewRepresentable`, selectable and not editable. `Block.parse` is kept as the markdown
splitter; only the output changes from SwiftUI views to one `NSAttributedString`.

## Task 1: Save spec documentation

Create `agent-os/specs/2026-09-15-0219-summary-text-size-and-highlights/` with:

- **plan.md**: this plan.
- **shape.md**: scope, the decisions above, the macOS 14.4 constraint.
- **standards.md**: repo conventions that apply (Theme as the only place for colors and metrics,
  stable UserDefaults keys, sessions self-contained on disk with no database, swift-testing with
  hardcoded expectations, Spanish UI strings with English code, Conventional Commits).
- **references.md**: `MarkdownText.swift` (block parser), `SessionMetadata.swift` (sidecar
  load/save idiom), `Preferences.swift` (persisted preference idiom), `Session.audioFile(among:)`
  (why the file name must start with `transcript.`), `Components.swift` (`TabStrip` trailing slot,
  `IconButton`, `CopyButton`).
- No `visuals/`.

## Task 2: Highlights model and persistence

New `app/Sources/RecordTranscriber/Library/SummaryHighlights.swift`.

- `SummaryHighlights: Codable, Equatable` with `summarySHA256: String` and
  `highlights: [Highlight]`; `Highlight` holds `location`, `length` (UTF-16 offsets into the
  **rendered** summary string, which is what `NSTextView.selectedRange` reports), `color`, and the
  highlighted `text`.
- `enum HighlightColor: String, Codable, CaseIterable { yellow, green, pink, blue }` with Spanish
  display names for the menu.
- `apply(_ color:, to range: NSRange)` and `remove(in range: NSRange)` keep the list
  normalized: sorted, no overlaps (a new mark overwrites the overlapped part of older ones,
  splitting them), adjacent runs of the same color merged. Pure functions, no AppKit.
- File name `transcript.summary.highlights.json` (add `Session.highlightsURL`). The `transcript.`
  prefix is required: `Session.audioFile(among:)` treats any other unknown file in an import's
  folder as a candidate recording, and a `highlights.json` would sort ahead of the audio.
- `load(for session:, summary:, rendered:)`: returns an empty set when the file is missing or
  malformed (same stance as `SessionMetadata.load`), when `summarySHA256` differs from the current
  `transcript.summary.md` (this is "a regenerated summary starts clean", and it holds whichever
  path rewrote the summary: Resumir de nuevo, Transcribir de nuevo, or the CLI), and drops any
  highlight whose range no longer holds its `text` in the rendered string (guards against a later
  change to the renderer shifting offsets). SHA-256 via CryptoKit, a system framework.
- `save(to folder:)` with pretty-printed sorted keys; saving an empty list deletes the file so a
  session with no marks has no stray sidecar.

Tests in `app/Tests/RecordTranscriberTests/SummaryHighlightsTests.swift`: apply on empty; apply
overlapping a different color splits the old mark; apply adjacent same color merges; remove in the
middle of a mark splits it; remove over nothing is a no-op; round trip with the full expected JSON
literal; changed summary hash loads empty; mismatched `text` is dropped while the others stay;
malformed file loads empty; saving empty removes the file. Plus one case in `SessionTests` that
`audioFile(among:)` ignores `transcript.summary.highlights.json`.

## Task 3: Summary font size preference

In `Preferences.swift`: `Key.summaryFontSize = "summaryFontSize"`, `summaryFontSize: Double`
persisted in `didSet`, default 12 (today's `Theme.bodyFont`), and `static let summaryFontSizes =
10.0...24.0` with `increaseSummaryFontSize()` / `decreaseSummaryFontSize()` stepping by 1 and
clamping. Tests in `PreferencesTests`: default, persisted value read back through a fresh instance
on the same suite, clamping at both ends, a stored out-of-range value clamped on load.

## Task 4: Render the summary as an attributed string

Rework `Views/MarkdownText.swift` into the renderer (keep the file and `Block.parse` unchanged; the
SwiftUI `body` goes away because the view is replaced in Task 5):

- `static func attributedString(markdown:, fontSize:) -> NSAttributedString`: blocks joined by
  newlines; heading sizes keep today's proportions to the body (17 / 14 / 12.5 over 12), semibold;
  bullets use a paragraph style with a head indent so wrapped lines align after the marker;
  paragraph spacing from `Theme.Space.sm`; color `Theme.textPrimary`, marker `Theme.textTertiary`.
- Inline markup still goes through `AttributedString(markdown:)` with
  `inlineOnlyPreservingWhitespace`, but its `inlinePresentationIntent` has to be mapped to AppKit
  fonts by hand (bold, italic, monospaced code) since `NSTextView` does not render the intent; links
  keep `.link`.
- Add `Theme.highlight(_ color: HighlightColor) -> Color`, translucent enough to read light text
  over the dark panel, and `Theme.selection` for the text view's selected-text background.

Tests (new `MarkdownTextTests.swift`): the rendered plain string for a sample with a heading,
bullets, an ordered item and bold text equals a hardcoded literal; the heading font size at
`fontSize: 18` is 25.5 and body 18. These pin the offsets highlights depend on.

## Task 5: Summary text view, context menu, size controls

New `Views/SummaryTextView.swift`: `NSViewRepresentable` returning an `NSScrollView` around an
`NSTextView` subclass (not editable, selectable, `drawsBackground = false`, insets matching
`Theme.panelPadding + Theme.Space.sm`, `selectedTextAttributes` from `Theme.selection`).

- Inputs: `markdown`, `fontSize`, `highlights`, and `onChange: (SummaryHighlights) -> Void`.
  `updateNSView` rebuilds the text storage only when markdown, size or highlights changed, then
  adds `.backgroundColor` for each highlight. Preserve the scroll position across a size change.
- The subclass overrides `menu(for:)` to prepend, when the selection is non-empty,
  `Resaltar ▸ Amarillo / Verde / Rosa / Azul` and, when the selection touches a mark,
  `Quitar resaltado`, followed by the system items (Copiar, Buscar...).
- A coordinator applies the edit through `SummaryHighlights`, saves, and calls back.

`SessionDetailView.swift`:

- Summary tab uses `SummaryTextView` instead of `ScrollView { MarkdownText }`; the transcript tab is
  unchanged.
- `@State` holds the loaded `SummaryHighlights`, loaded on appear and whenever the session or its
  summary text changes (a regeneration reloads it and the hash check empties it).
- `tabs(copyable:)` trailing slot shows, on the summary tab only, two `IconButton`s
  (`textformat.size.smaller` "Reducir texto", `textformat.size.larger` "Aumentar texto") with
  `.keyboardShortcut("-")` and `.keyboardShortcut("+")`, disabled at the range limits, then the
  copy button. Confirm ⌘+ works on the owner's Spanish keyboard layout during verification; if it
  does not, add `"="` as the alternate.
- Save failures surface through `model.failure`, like other file errors, not swallowed.

## Task 6: Docs

Add a short entry to `agent-os/product/roadmap.md` under Phase 2 pointing at the spec folder, in
the same voice as the other entries.

## Commits

Atomic Conventional Commits: `docs: record the summary highlights spec`, `feat(app): persist
summary highlights per session`, `feat(app): remember the summary text size`, `refactor(app):
render the summary as an attributed string`, `feat(app): highlight and resize the summary text`,
`docs: note summary highlights in the roadmap`.

## Verification

1. `make test` (Go and Swift suites) green.
2. `make run`, open a session with a summary:
   - A+ / A− and ⌘+ / ⌘− resize headings and body together, stop at 10 and 24, and the size is the
     same after switching sessions and relaunching.
   - Select text, right-click, `Resaltar ▸ Verde`: the mark appears. Overlap it with yellow, remove
     part of it, relaunch: marks come back exactly, at every font size.
   - `transcript.summary.highlights.json` exists in the session folder; `transcript.summary.md`
     is byte-identical to before (`git diff --no-index` or `shasum`).
   - An imported session with highlights still resolves its audio (Transcribir de nuevo works).
   - "Resumir de nuevo": the new summary shows no marks.
   - The transcript tab is unchanged: fixed size, selectable, no highlight menu.
