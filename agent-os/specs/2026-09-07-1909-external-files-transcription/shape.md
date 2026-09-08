# External Files Transcription — Shaping Notes

## Scope

Add a section to `Record Transcriber.app` for transcribing audio that was not recorded in the app:
WhatsApp voice notes, `.m4a` and `.mp3` files, the occasional video. The user picks or drops one or
more files, the app copies each into its own folder and transcribes it, and the transcript is
readable and copyable from the same window that lists recordings.

The pipeline and the CLI are untouched. `transcribe` already accepts any container, already writes
outputs wherever `-o` points, and already produces a summary from a written transcript. This is
app work: a second library, a queue, three entry points, naming, and the repair of the half-feature
that drag-and-drop already was.

## Decisions

**An own section, not the recordings list.** Imported files live under `<library>/Archivos/<name>/`
and are listed under "Archivos", beside "Grabaciones" rather than among them. The two alternatives
were an ephemeral tool that shows the transcript and keeps nothing, and listing imports among the
recordings with a mark. The first was rejected because a voice note is something the user comes
back to; the second because a list of meetings and a list of forwarded audios answer different
questions, and a mark on every row is a filter nobody asked for. A subfolder rather than a sibling
folder because the library folder is the one preference about location, and one folder is what a
backup or a move has to carry.

**Transcript by default, summary on demand.** An import runs with `-summary none`. A "Resumir"
button in the detail view runs the CLI again with the transcript as input, which skips ffmpeg and
whisper and takes seconds (`cmd/transcribe/main.go:171`). Running the full pipeline as recordings
do was rejected because a forty-second voice note does not need minutes, and every summary is a
`claude` call. The kind is the one in Preferences; `none` falls back to `auto` because the CLI
rejects a transcript input with no summary kind (`main.go:272`), and a button that does nothing is
worse than a button that picks the sensible kind.

**Several files, one after another.** WhatsApp forwards arrive in batches. The queue drains
sequentially because the pipeline runs one whisper process at a time by design, and a drop while
the queue is draining extends it rather than being refused. Progress reads "Transcribiendo archivo
n de m" and there is a cancel: the current CLI is sent SIGTERM (it removes its intermediate WAV),
the rest of the queue is dropped, and the item keeps its audio with the "sin transcribir" badge, so
nothing is lost and nothing is half-written.

**Three ways in.** A "Transcribir archivo…" button in the sidebar, drag-and-drop onto the window
accepting several items, and a row in the menu bar panel that opens the file dialog and then the
window on the first import. The dialog is one `NSOpenPanel` helper shared by the panel and the
window. SwiftUI's `.fileImporter` was the alternative: it is tied to the view that presents it, and
the `MenuBarExtra` popover closes when the dialog takes key, so the panel would need its own copy
of the state and the "open the window afterwards" step would be split across two call sites.

**Name by file, or by date, and rename afterwards.** A preference chooses the default: the file's
stem (`PTT-20260901-WA0003`, the default) or the import time in the recordings' `yyyy-MM-dd HHmm`
form. Either can be renamed later from the row's context menu or the detail header. Rename moves
the folder, because the folder is the source of truth and a name kept anywhere else would be a
second source. Asking for a name at import time was rejected: with several files it becomes a
dialog per file. Rename is offered to recordings too, since it costs the same.

**Copy, not reference.** The file is copied into its folder so the folder stays self-contained,
the property the library already relies on. On the same APFS volume a copy is a clone and costs
nothing; across volumes it is a real copy and runs off the main actor.

**No new visual design.** Rows, badges, the detail pane and the theme are reused. The tab strip in
the detail view becomes a component so the sidebar's section switch is the same control.

**The Go CLI is untouched.** The roadmap records this as Phase 2.6, app only. "Batch mode" for the
CLI stays in Phase 3.

### The repair

Drag-and-drop already called `AppModel.importFile`, which copied the file under its own name into
a date-named session and ran the full pipeline. `Session.audioURL` was hardcoded to `audio.opus`,
so the imported session read "sin audio", its reload button stayed disabled, and it could never be
transcribed again. `Session` now resolves its audio from the folder listing: `audio.opus` when
present, otherwise the one file the app did not derive. The pipeline's `input` event carries the
file's duration and the app discarded it; it is now kept, so imports show a length.

## Context

- **Visuals:** none. The existing design is reused.
- **References:** see `references.md`.
- **Product alignment:** Phase 2.6 of `agent-os/product/roadmap.md`, app only. Inside the stated
  constraints: no third-party packages, no Xcode project, the CLI remains the one pipeline.

## Standards Applied

`agent-os/standards/index.yml` is empty, so no standards were pulled in. `standards.md` records the
conventions the existing code holds itself to, which this work continues.
