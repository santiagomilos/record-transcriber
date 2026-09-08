# External files: transcribe audio that was not recorded in the app

## Context

The app records meetings and runs the pipeline over the recording. The user also needs to transcribe audio that already exists elsewhere: WhatsApp voice notes (`.opus`), `.m4a`/`.mp3` files, the occasional video. The Go CLI already accepts any container (ffmpeg normalizes it; `cmd/transcribe/main.go:222-224` has no media allowlist), so this is app work only.

The window already has a half-feature for this: dragging a file onto `LibraryView` calls `AppModel.importFile` (`app/Sources/RecordTranscriber/AppModel.swift:114`), which copies the file into a new date-named session and runs the full pipeline, summary included. It is undiscoverable (no button, no menu row), accepts one file, and produces a broken session: the copy keeps its original name while `Session.audioURL` is hardcoded to `audio.opus` (`Library/Session.swift:9,41,50`), so the row reads "sin audio", the reload button stays disabled, and re-transcribing is impossible. Imported sessions also show no length because `TranscribeRunner.apply` ignores the `input` event that carries `duration_ms` (`Pipeline/TranscribeRunner.swift:157`).

Shaping happened with the user on 2026-09-07 (`/agent-os:shape-spec`). Decisions:

1. **Own section.** A second list, "Archivos", separate from "Grabaciones", stored under `<libraryFolder>/Archivos/<name>/`. History is kept but voice notes never mix with meetings.
2. **Transcript only by default; summary on demand.** Imports run with `-summary none`. A "Resumir" button in the detail view runs the CLI over the existing transcript (`.srt` preferred, `.txt` fallback), which the CLI already supports (`main.go:171 summarizeTranscript`, honors `-o`, writes `<outputBase>.summary.md`) and takes seconds. Kind comes from preferences; `none` falls back to `auto` because the CLI rejects `none` with a transcript input (`main.go:272`).
3. **Several files, sequential queue**, with a visible "n de m" and a cancel.
4. **Three entry points:** a "Transcribir archivo…" button in the window sidebar, multi-file drag-and-drop onto the window, and a row in the menu bar panel that opens the file dialog and then the window.
5. **Naming:** a preference picks the default name for imports (original file stem, default, or import date like recordings); any item can be renamed afterwards. Rename moves the folder: the folder stays the source of truth.
6. **No new visual design.** Reuse `PanelRow`, `StatusBadge`, `SessionDetailView`, `Theme`.
7. **Go CLI untouched.** Roadmap gets a "Phase 2.6" entry (app only); CLI batch mode stays in Phase 3.

Verified on this machine: `.opus/.ogg/.m4a/.mp3/.wav/.aac/.amr/.flac` conform to `UTType.audio`; `.mp4/.mov/.webm/.3gp` to `.movie`. `[.audio, .movie]` is the right filter for both the dialog and the drop.

Design choices (one line each, alternative in parentheses):

- **Two `LibraryStore` instances**, `library` (recordings, skips the `Archivos` folder) and `imports` (`<lib>/Archivos`). The store an item came from is its kind. (One store with a `kind` per session forces every list and sort to filter.)
- **Audio resolved once in `Session.init`** by a pure function over the folder listing: `audio.opus` if present, else the first non-derived regular file, else `audio.opus` so the recorder keeps a write target. (Resolving on every access lists the folder per row per redraw; the detail view redraws on hover.)
- **`NSOpenPanel` helper** shared by the panel row and the sidebar button. (`.fileImporter` is tied to the presenting view; the `MenuBarExtra` popover closes when the dialog takes key.)
- **Queue drains inside `AppModel`**; a drop while draining extends the queue. (Refusing while busy turns "drop three more" into an error.)
- **Section state lives in `AppModel.librarySection`** so the panel row and an import can switch the sidebar. (`@State` in the view cannot be flipped from the panel.)
- **Rename via `.alert` with a `TextField`**, from the row context menu and a pencil in the detail header, for both lists. (Inline editable title needs a text-field style the theme lacks.)
- **Copy, not reference.** Same-volume APFS copies are clones; cross-volume copies run off the main actor. The folder stays self-contained.

## Task 1: Save spec documentation

Create `agent-os/specs/2026-09-07-1909-external-files-transcription/` following the format of `agent-os/specs/2026-09-01-0524-adaptive-summaries/`:

- `plan.md`: this plan.
- `shape.md`: scope, the seven decisions above with the reasoning, context (visuals: none; references; product alignment: Phase 2.6, app only).
- `standards.md`: `agent-os/standards/index.yml` is empty, so restate the conventions the code holds itself to (no third-party packages, folder on disk is the source of truth, comments say what the reader cannot see, deterministic tests with literal expectations, Spanish UI strings and English code), modeled on the panel-redesign spec's `standards.md`.
- `references.md`: `AppModel.importFile`, `Session`, `LibraryStore`, `TranscribeRunner.apply`, `SessionDetailView.tabs`, `PreferencesView.fileImporter`, and `cmd/transcribe/main.go summarizeTranscript` with why each matters.
- No `visuals/`.

## Task 2: Session resolves its audio and its name

`app/Sources/RecordTranscriber/Library/Session.swift`

- Add a pure `static func audioFile(in folder: URL, contents: [String]) -> String`: `audio.opus` if listed; else the sorted first name that is not `meta.json`, does not start with `transcript.` (this also excludes the pipeline's temporary `transcript.16k.wav`), does not end in `.part`, does not start with `.`; else `audio.opus`. A convenience overload lists the folder (`[]` on error).
- `audioURL` becomes a `let` set in `init(folder:)`. `hasAudio` and `status` are unchanged in shape.
- `displayName`: date label when the folder name is a date name (plain or with the ` N` collision suffix from `createSession`), otherwise the folder name verbatim. `startDate(ofFolder:)` strips the suffix before parsing, so `2026-09-01 0314 2` stops falling back to the creation date.
- Update the type's doc comment: an imported file keeps its own name inside the folder, which is why the audio is resolved rather than assumed.

`app/Sources/RecordTranscriber/Library/SessionMetadata.swift`

- Add `var sourceName: String?` (the original file name with extension), omitted from JSON when nil so the existing literal test still passes. Fix the `durationSeconds` comment: an import gets its length from the pipeline's `input` event.

## Task 3: LibraryStore lists two folders, creates named sessions, renames

`app/Sources/RecordTranscriber/Library/LibraryStore.swift`

- `static let importsFolderName = "Archivos"`, `static func importsFolder(in library: URL) -> URL`.
- `init(folder:excludedFolderNames: Set<String> = [])`; `reload()` filters those names out.
- Factor the suffix loop of `createSession(startedAt:)` into `private func freeFolder(named:) -> URL`; add `createSession(named:)`, and make the dated one call it with `Session.folderName(for:)`.
- `rename(_:to:) throws -> Session`: trim; throw `LibraryError.invalidName` (Spanish `errorDescription`) when empty, leading `.`, contains `/` or `:`, or equals an excluded name; no-op when unchanged; otherwise `moveItem` to `freeFolder(named:)`, reload, return the new `Session`.

## Task 4: Pipeline and preferences

`app/Sources/RecordTranscriber/Pipeline/TranscribeRunner.swift`

- `run(input:outputBase:preferences:summaryKind: String? = nil)` passes the override through.
- Keep `inputDurationMS` from the `.input` event (reset per run); the `.transcript` case builds `Result` with it. Make `apply` internal so a test can fold two events without spawning a process.

`app/Sources/RecordTranscriber/Preferences/Preferences.swift`

- `Key.importNaming = "importNaming"`; `enum ImportNaming: String, CaseIterable { case fileName, date }` with `name(for url: URL, at date: Date) -> String` (stem, falling back to the date name when the stem is empty; or `Session.folderName(for:)`). Default `.fileName`.
- `var onDemandSummaryKind: String { summaryKind == "none" ? "auto" : summaryKind }`.
- `transcribeArguments(input:outputBase:summaryKind: String? = nil)`: only the `-summary` value changes; flag order stays so `rendersTheDefaultsAsTranscribeFlags` keeps pinning it.

## Task 5: AppModel owns the queue, the section, summarize and rename

`app/Sources/RecordTranscriber/AppModel.swift`

- New state: `let imports: LibraryStore`; `var librarySection: LibrarySection` (`.recordings`/`.imports`); `private(set) var importProgress: ImportProgress?` (`done`, `total`); private `pendingImports: [URL]` and `cancellingImports`.
- `init`: `library` excludes `LibraryStore.importsFolderName`; `imports` points at `LibraryStore.importsFolder(in:)`.
- `isBusy` also covers `importProgress != nil`, so "Grabar" stays disabled between queue items.
- `syncFolders()` replaces the two `library.folder = preferences.libraryFolder` lines and assigns both stores only when changed; `setLibraryFolder(_:)` for `PreferencesView`.
- `selectedSession` searches both stores; `delete` and `transcribe` reload the owning store (`store(owning:)` compares the parent folder with `imports.folder`).
- `importFiles(_ urls: [URL]) async`: refuse while recording (message); keep URLs conforming to `.audio`/`.movie`; refuse URLs inside the library folder (the app's own `audio.opus`); append to the queue; set `librarySection = .imports`; if already draining, bump `total` and return; else drain sequentially through `importOne`, clearing `importProgress` at the end.
- `importOne(_:)`: name per `preferences.importNaming`; `imports.createSession(named:)`; copy on a detached task; save `SessionMetadata(sourceName:)`; rebuild `Session(folder:)` so the audio resolves; select it; `runner.run(..., summaryKind: "none")`; `recordResult`; reload `imports` on both paths; suppress the failure alert when cancelling.
- `cancelImports()`: empty the queue, flag cancelling, `runner.cancel()`. The CLI writes outputs only after the decode, so the item keeps its audio and shows "sin transcribir".
- `summarize(_:) async`: `.srt` if present else `.txt`; `runner.run(input: transcript, outputBase: session.transcriptBase, preferences:, summaryKind: preferences.onDemandSummaryKind)`; reload the owning store. `runner.result` stays nil on this path, so `recordResult` is skipped and metadata is not clobbered.
- `rename(_:to:)`: guard `!isBusy`; delegate to the owning store; move `selection` to the new id; errors to `failure`.
- Delete `importFile(_:)`.

## Task 6: Views

New `app/Sources/RecordTranscriber/Views/MediaFilePicker.swift`: `enum MediaFilePicker { @MainActor static func chooseFiles() -> [URL] }` wrapping `NSOpenPanel` (multiple selection, no directories, `allowedContentTypes = [.audio, .movie]`, `prompt = "Transcribir"`, `NSApplication.shared.activate(ignoringOtherApps: true)` first as `MenuBarView.openLibrary` already does). Comment why not `.fileImporter`.

`app/Sources/RecordTranscriber/Views/Components.swift`: extract the tab strip from `SessionDetailView.tabs` (lines 90-120) into a generic `TabStrip` with a trailing view builder, used by the detail view (with `CopyButton`) and by the sidebar (sections). One strip, two places, per the "components before copies" convention.

`app/Sources/RecordTranscriber/Views/LibraryView.swift`

- Sidebar header: `TabStrip` over `Grabaciones | Archivos` bound to `model.librarySection`, then the section's action (`recordButton`, or `Transcribir archivo…` calling `MediaFilePicker` then `model.importFiles`), plus, while `importProgress` is set, "Transcribiendo archivo n de m" with a plain "Cancelar".
- The list reads the active store's sessions; rows unchanged. Empty state per section ("Sin archivos" / "Elige Transcribir archivo… o arrastra aquí audio o video.").
- Context menu gains "Renombrar…" (disabled while busy). `.alert("Renombrar", presenting:)` with a `TextField` and Renombrar/Cancelar.
- `SessionDetailView(...).id(session.id)` so tab state resets per session.
- `onDrop(of: [.audio, .movie])` loads every provider's URL (continuation around `loadObject`), preserves order, calls `importFiles`.

`app/Sources/RecordTranscriber/Views/SessionDetailView.swift`

- Initial tab: summary when one exists, transcript otherwise.
- Header: pencil `IconButton` for rename; a "Resumir" / "Resumir de nuevo" button when a `.srt` or `.txt` transcript exists, disabled while busy or when `claude` is missing (`model.missingTools`).
- `facts` prepends `metadata.sourceName`. Summary-tab placeholder reads "Pulsa Resumir para generarlo." when a transcript exists. "n de m" caption under `PhaseProgress` while importing.

`app/Sources/RecordTranscriber/Views/MenuBarView.swift`

- Idle state card: second `PanelRow` "Transcribir archivo…" (subtitle "Audio o video existente", disabled while busy) → `MediaFilePicker`, `openLibrary()`, `model.importFiles`. Running card shows "Archivo n de m" under the phase. `openLibrary(selecting:)` sets the recordings section.

`app/Sources/RecordTranscriber/Views/PreferencesView.swift`

- `SettingRow(label: "Archivos")` with a picker "Nombre original" / "Fecha" over `ImportNaming.allCases`; folder change calls `model.setLibraryFolder`.

## Task 7: Tests (swift-testing, temp dirs, literal expectations)

- `SessionTests.swift`: audio resolution cases (recorder file wins; imported file survives `meta.json`, `transcript.*`, `transcript.16k.wav`, `.DS_Store`; a `.part` alone resolves to `audio.opus` so status stays `.capturing`; empty folder; first by name among several); an imported folder reports `.needsTranscription`; display names for a date folder, a suffixed date folder and a plain name.
- New `LibraryStoreTests.swift`: skips `Archivos` when listing recordings; lists imports in their folder; `createSession(named:)` suffixes a collision; creates the imports folder on first use; rename moves the folder and updates the list; rename collision suffixes; rejects empty, slashed and excluded names; same-name rename is a no-op.
- `PreferencesTests.swift`: default `importNaming`; persistence; `name(for:at:)` for stem, date and empty stem; `onDemandSummaryKind` for `none` and `minuta`; `transcribeArguments` with the override as a full literal list.
- New `TranscribeRunnerTests.swift` (`@MainActor`): `input` then `transcript` events yield `Result(language: "es", segments: 167, durationMS: 963000, elapsedMS: 103000)`; no `input` event yields duration 0.
- `SessionMetadataTests.swift`: `sourceName` round trip; omitted when nil.

## Task 8: Docs

- `README.md` "The app": replace the drag sentence with a paragraph on the "Archivos" section (where files land, transcript only, Resumir on demand over the transcript, queue, three entry points, naming preference and rename, copied so the folder is self-contained). "Test" paragraph mentions audio resolution and import naming.
- `agent-os/product/roadmap.md`: "Phase 2.6: Files that were not recorded here — shipped", app only; "Batch mode" stays in Phase 3.

## Verification

1. `make test` (Go unchanged but run anyway; Swift covers Tasks 2-4 and 7).
2. `make run`, then from the panel row pick one WhatsApp `.opus`: the window opens on "Archivos", the row carries the file's stem, progress runs, the transcript appears, the facts line shows the length and the source name.
3. Drop three files at once onto the window: "Transcribiendo archivo 1 de 3" advances; cancel on the second; the third is never started and the second shows "sin transcribir" with its audio intact and no alert.
4. With `Resumen` set to "Ninguno" in preferences, press Resumir: the summary appears in seconds and the summary tab becomes the default for that item.
5. Rename an import from the context menu; the folder moves in the Finder; a name that collides gets ` 2`; rename is disabled while a run is active.
6. Record a short meeting: it lists under "Grabaciones", not under "Archivos", and `Archivos` never appears as a recording.

## Risks and edge cases

- A `formats` preference without `txt` leaves `hasTranscript` false; the Resumir condition checks `.srt` or `.txt`, but `status` still reads "sin transcribir". Left as is, noted.
- Cross-volume copies of large videos take real time with no percentage; the caption shows "Archivo n de m" meanwhile.
- The panel's "Recientes" keeps listing recordings only; adding imports there is a one-line follow-up.
- Rename is offered for recordings too; a recording renamed to a non-date name sorts by folder creation date and shows the raw name.
