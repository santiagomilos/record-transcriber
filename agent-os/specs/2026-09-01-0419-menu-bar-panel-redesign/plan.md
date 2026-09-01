# Menu bar panel redesign

## Context

`Record Transcriber.app` works, but its menu bar panel is a `VStack` of three stock SwiftUI
buttons — `Grabar`, `Abrir grabaciones`, `Salir` — at `app/Sources/RecordTranscriber/Views/MenuBarView.swift:9-55`.
It reads as a prototype: default bordered buttons, no hover states, no identity, no way to
reach Preferences (the `Settings` scene exists but nothing opens it), and no sight of the
library without opening a separate window.

The reference is the JetBrains Toolbox panel: a branded header, grouped cards, a primary
action that states what it does, and a list of items with real metadata. This work rebuilds
the panel and the `Grabaciones` window on a shared dark design system, adds the metadata the
richer rows need, and makes the menu bar icon report state on its own.

Two decisions taken during shaping, both deliberate:

- **The panel and window commit to a dark palette of their own** rather than following the
  system appearance. It buys the Toolbox identity; the cost is a theme maintained by hand
  and a panel that stays dark in Light Mode.
- **Duration comes from a `meta.json` sidecar**, not from probing the audio. The recordings
  are Ogg/Opus, which AVFoundation cannot read, so the alternative was an `ffprobe`
  subprocess per row on every panel open. The sidecar also captures the detected language
  and segment count that `PipelineEvent` already carries and `TranscribeRunner.apply`
  currently discards (`Pipeline/TranscribeRunner.swift:113-137`). Sessions recorded before
  this change simply show no duration.

## Task 1: Save spec documentation

Create `agent-os/specs/2026-09-01-0419-menu-bar-panel-redesign/` with:

- **plan.md** — this plan.
- **shape.md** — scope, the four shaping decisions (full Toolbox-style panel; own dark
  theme; `meta.json` sidecar; accessory app), and the context they came from.
- **standards.md** — `agent-os/standards/index.yml` is empty, so this restates the repo's own
  conventions as `agent-os/specs/2026-09-01-0255-macos-recording-app/standards.md:1-4` does,
  plus what this work adds: design tokens live in one file, no third-party packages, view
  code holds no state the model does not.
- **references.md** — the existing spec folder, `Views/MenuBarView.swift` (the level meter
  rationale to preserve), `Library/Session.swift` (folder-is-the-truth), and the JetBrains
  Toolbox panel as the visual reference.
- **visuals/** — copy `3.png` (current panel) and `4.png` (Toolbox reference) from
  `/Users/santi/.claude/image-cache/df1810ad-4729-4520-a149-283037026585/`, renamed
  `current-panel.png` and `toolbox-reference.png`.

## Task 2: Session metadata on disk

New `app/Sources/RecordTranscriber/Library/SessionMetadata.swift`:

```swift
struct SessionMetadata: Codable, Equatable {
    var durationSeconds: Double
    var language: String?
    var segments: Int
}
```

Written as `meta.json` in the session folder. Add `SessionMetadata.load(from folder:)` →
`SessionMetadata?` (a missing or malformed file is `nil`, never an error — same posture as
`LibraryStore.reload`, `Library/LibraryStore.swift:24-34`) and `save(to folder:)`.

In `Library/Session.swift`:

- Load the sidecar in `init(folder:)` into a stored `metadata: SessionMetadata?`, alongside
  the existing `startedAt`.
- Add `enum Status { case recording, needsTranscription, ready, complete }`, derived from the
  files already checked there: `audio.opus.part` present → `.recording`; `hasSummary` →
  `.complete`; a `transcript.txt` → `.ready`; `hasAudio` only → `.needsTranscription`.

New `app/Sources/RecordTranscriber/Library/SessionDateFormat.swift` — a pure
`label(for date: Date, now: Date = Date(), locale:)` returning `hoy 14:32`, `ayer 09:10`, or
`28 ago 15:40`. Taking `now` as a parameter is what makes it testable without `Date()`.

## Task 3: Capture the metadata

In `Pipeline/TranscribeRunner.swift`, keep the `transcript` event instead of dropping it:
add `private(set) var result: TranscriptResult?` (`language`, `segments`, `durationMS`,
`elapsedMS`) and populate it in `apply` under a new `case .transcript`. Reset it in `run`
next to `outputs = [:]`.

In `AppModel.swift`:

- `stopRecording()` writes `SessionMetadata(durationSeconds: recorder.elapsed, ...)` before
  calling `transcribe(session)`. The elapsed value has to be read before `recorder.stop()`
  resets it.
- `transcribe(_:)` merges `runner.result` into the session's sidecar after a successful run,
  so language and segment count land even for imported files.

## Task 4: The design system

New `app/Sources/RecordTranscriber/Views/Theme.swift` — the only file allowed to name a raw
color or a magic number:

- **Palette**: panel background, card background, card border, row hover, primary/secondary/
  tertiary text, accent, recording red, warning amber. Values sampled from the Toolbox
  reference, expressed as `Color(red:green:blue:)`.
- **Metrics**: panel width (320), corner radii, row height, the spacing scale.
- **Typography**: the three or four text styles the panel uses.

New `app/Sources/RecordTranscriber/Views/Components.swift`:

- `PanelCard` — a grouped container: card fill, 1 pt border, rounded corners.
- `PanelRow` — icon, title, optional subtitle, optional trailing; hover highlight via
  `.onHover`; used by both the panel actions and the recent list.
- `StatusBadge` — one `Session.Status` as a pill.
- `RecordControl` — the primary action, in its idle / recording / busy forms.
- Restyled `LevelMeter`, moved here from `MenuBarView.swift:83-117`. Keep the two-bar shape
  and the dB curve; the comment explaining why one mixed bar hides the common failure stays.

Everything applies `.environment(\.colorScheme, .dark)` at the root of each scene, so system
controls that slip through render dark too.

## Task 5: Rebuild the panel

Rewrite `Views/MenuBarView.swift` as, top to bottom:

1. **Header** — app mark, `Record Transcriber`, and trailing icon buttons: `SettingsLink`
   (gear, ⌘,) and quit (⌘Q). This is the first time Preferences is reachable from the menu.
2. **Primary card** — idle: `Grabar` with the subtitle `Micrófono + sistema`, ⌘R. Recording:
   pulsing red dot, elapsed time, `LevelMeter`, `Detener` (⌘R) and `Descartar grabación`.
   Transcribing: `runner.phase.label`, the progress bar, and the percentage.
3. **Banners** — the failure banner (keeping the comment at `MenuBarView.swift:11-13` on why
   it is repeated here) and the missing-dependencies warning, both as styled cards.
4. **Recientes** — the five newest `model.library.sessions` as `PanelRow`s: display label from
   `SessionDateFormat`, duration and language from the sidecar, `StatusBadge`. Clicking one
   sets `model.selection` and opens the library window. Empty library shows one quiet line.
5. **Footer** — `Abrir biblioteca` (⌘O).

Panel background painted with `.ignoresSafeArea()` at the outermost level so it reaches the
popover's rounded corners.

## Task 6: Menu bar icon states

In `RecordTranscriberApp.swift:20-31`, replace the plain symbol swap:

- Idle: `waveform`.
- Recording: `record.circle.fill` with `.symbolEffect(.pulse, options: .repeating)`, and the
  elapsed time as text next to it, so a running recording is visible without opening
  anything.
- Transcribing: `waveform` with `.symbolEffect(.variableColor.iterative, options: .repeating)`.

If `MenuBarExtra`'s label rejects the effects (its label view is rendered as a template
image and animation support there is not guaranteed), fall back to swapping symbols on a
timer and keep the elapsed-time text, which carries most of the signal.

## Task 7: Accessory app

Add `LSUIElement` to `app/Resources/Info.plist`. The app then lives only in the menu bar.

Consequence to handle: an accessory app does not come to the front on its own, so every
`openWindow(id: LibraryWindow.id)` and `SettingsLink` needs
`NSApp.activate(ignoringOtherApps: true)` beside it or the window opens behind whatever is
in front.

## Task 8: Apply the theme to the window

`Views/LibraryView.swift` and `Views/SessionDetailView.swift`:

- Sidebar rows use the same `PanelRow` and `StatusBadge`, with the display label, duration
  and status replacing the raw folder name at `LibraryView.swift:95-113`.
- Detail header: title, date, duration, language, segment count from the sidecar.
- Render the summary as Markdown with `AttributedString(markdown:)` — Foundation, no
  dependency — instead of the plain `Text` at `SessionDetailView.swift:57-62`. The transcript
  stays plain and selectable.
- Restyle `MissingToolsView`, the empty states and the toolbar against the palette;
  `.toolbarBackground` and the dark color scheme on the window root.

## Task 9: Tests and docs

Add to `app/Tests/RecordTranscriberTests/`, following the existing style — fixed dates,
literal expectations, one scenario per test:

- `SessionMetadataTests` — round trip through `meta.json`; a missing file is `nil`; malformed
  JSON is `nil`.
- `SessionDateFormatTests` — a fixed `now` against a same-day, previous-day and older date,
  each asserting the literal string.
- `SessionTests` — add status derivation for each combination of files present.
- `PipelineEventTests` — add a `transcript` event line, asserting language, segments and
  `durationMS` decode.

Update `README.md` (the app section: panel contents, Preferences reachable, no Dock icon) and
`agent-os/product/roadmap.md` (a Phase 2 note that the app UI was reworked, and the sidecar).

## Verification

1. `make test` — Go plus Swift suites green.
2. `make app && make run`. Open the panel: header, Preferences and quit reachable, recent
   recordings listed with date, duration and status.
3. Record ~20 s. The menu bar icon shows the recording state and the elapsed time; the panel
   shows the timer and both level bars moving — speak into the microphone and play something
   with sound to confirm the two bars move independently.
4. Stop. The panel switches to the transcription phases with progress; when it finishes,
   `meta.json` exists in the session folder with a duration close to 20 s and a language.
5. Click the new session in the panel — the library window comes to the front with it
   selected, the summary renders as Markdown, the sidebar row shows the same metadata.
6. Confirm no Dock icon and no ⌘Tab entry.
7. Switch the system to Light Mode and reopen the panel: it stays dark, by design.
