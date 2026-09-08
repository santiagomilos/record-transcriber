# References for External Files Transcription

## Code in this repo

### The import that already existed

- **Location:** `app/Sources/RecordTranscriber/AppModel.swift`, `importFile(_:)` (line 114 before
  this work) and `LibraryView.handleDrop` (`Views/LibraryView.swift:137`).
- **Relevance:** the path being replaced. It copied the file under its original name into a
  date-named recording session and ran the full pipeline, summary included; it took the first
  dropped item only and did not reload the library when it failed.
- **Key patterns to keep:** `recordResult(in:)` folds the pipeline's language and segment count
  into the sidecar and is reused unchanged; the copy-then-run order stays, so the folder is
  self-contained before anything reads it.

### Session and LibraryStore

- **Location:** `app/Sources/RecordTranscriber/Library/Session.swift`,
  `app/Sources/RecordTranscriber/Library/LibraryStore.swift`.
- **Relevance:** where audio resolution, display names, the second library and rename belong.
- **Key patterns:** `status` reads the folder in the order the pipeline fills it; `reload` rebuilds
  the list from disk; `createSession` appends a counter until the folder name is free, which is
  the loop rename and named creation share. `audioURL` was a constant, which is the defect that
  made imports unusable.

### The metadata sidecar

- **Location:** `app/Sources/RecordTranscriber/Library/SessionMetadata.swift`.
- **Relevance:** gains the original file name. Its doc comment already explains why a sidecar and
  not a database, and why a missing one is not an error; both hold for imports.

### TranscribeRunner and PipelineEvent

- **Location:** `app/Sources/RecordTranscriber/Pipeline/TranscribeRunner.swift`,
  `app/Sources/RecordTranscriber/Pipeline/PipelineEvent.swift`.
- **Relevance:** `apply` folds one event into published state and dropped the `input` event, which
  is the only one carrying the file's duration. The fixture in
  `app/Tests/RecordTranscriberTests/PipelineEventTests.swift` is a literal copy of a real stream
  and shows that the `transcript` event never carries `duration_ms`.

### Preferences

- **Location:** `app/Sources/RecordTranscriber/Preferences/Preferences.swift`.
- **Relevance:** the one place a preference becomes a CLI flag. `transcribeArguments` keeps its
  order so `PreferencesTests.rendersTheDefaultsAsTranscribeFlags` keeps pinning it; the summary
  override is a trailing optional parameter.

### The tab strip

- **Location:** `app/Sources/RecordTranscriber/Views/SessionDetailView.swift`, `tabs(copyable:)`.
- **Relevance:** the control that becomes `TabStrip` in `Components.swift` and is reused for the
  sidebar's Grabaciones | Archivos switch. Its comment about the copy button sitting with the tabs
  because it copies the open tab moves with it.

### The folder picker

- **Location:** `app/Sources/RecordTranscriber/Views/PreferencesView.swift`, `.fileImporter`.
- **Relevance:** the only file dialog before this work, and evidence that `.fileImporter` does
  present from inside the panel. It picks one folder from a view that stays alive; the media
  dialog is called from a panel row that disappears when the dialog takes key, which is why the
  media dialog uses `NSOpenPanel` instead.

### The CLI's transcript input

- **Location:** `cmd/transcribe/main.go`, `summarizeTranscript` (line 171) and `parseArgs`
  (line 226).
- **Relevance:** what "Resumir" calls. `-o` is honored for a transcript input, the summary is
  written to `<outputBase>.summary.md`, `-f`/`-l`/`-m` are ignored on that path, and `-summary
  none` is rejected at parse time. The `input` event with `duration_ms` is emitted only on the
  media path (`prepareAudio`, line 336).

### Prior specs, for document shape

- **Location:** `agent-os/specs/2026-09-01-0419-menu-bar-panel-redesign/`,
  `agent-os/specs/2026-09-01-0524-adaptive-summaries/`.
- **Relevance:** the `shape.md` / `standards.md` / `references.md` convention this spec follows,
  and the origin of "components before copies" and the sidecar decision.

## Platform facts verified for this spec

- `UTType(filenameExtension:)` on this machine (macOS 26.6) maps `.opus`, `.ogg` and `.oga` to
  `org.xiph.ogg-audio`, which conforms to `public.audio`; `.m4a`, `.mp3`, `.wav`, `.aac`, `.amr`,
  `.caf` and `.flac` conform to `public.audio`; `.mp4`, `.mov`, `.webm` and `.3gp` conform to
  `public.movie`. `[.audio, .movie]` covers WhatsApp exports and screen recordings alike.
