# Standards for External Files Transcription

`agent-os/standards/index.yml` contains no standards, so none were pulled in. What follows are the
conventions the existing code already holds itself to, which this work continues.

---

## Swift

- **No third-party dependencies.** SwiftUI, AppKit and Foundation ship with the platform. The file
  dialog is `NSOpenPanel`; the drop is `onDrop`; nothing is added to `Package.swift`.
- **The folder on disk is the source of truth.** A library is whatever folders exist under its
  root; a session's status is derived from which files it contains; a rename is a folder move. No
  state is kept that the Finder can invalidate. The one sidecar, `meta.json`, travels with the
  folder and its absence is never an error.
- **One pipeline.** The app spawns the bundled `transcribe` binary with the flags `Preferences`
  renders. A summary on demand is the same binary with the transcript as input, not a second code
  path.
- **Fail fast, and say so in the user's language.** A missing tool, a file that is not media, or
  an import attempted while recording is refused before any work starts, with a Spanish message in
  `failure`.
- **UI state is derived, not duplicated.** Views read `AppModel` and the stores; a view holds
  `@State` only for what is purely visual (the rename field, hover). The active section lives in
  the model because the panel has to be able to switch it.
- **Components before copies.** A control that appears in two places is one view used twice. The
  tab strip is extracted for that reason.
- **Comments say what the reader cannot see.** Doc comments describe what a call does for someone
  who will never open the body; inline comments carry a constraint or a rejected alternative, not
  narration. Why `NSOpenPanel` and not `.fileImporter`, why `transcript.` prefixes are excluded
  from audio resolution, why `none` becomes `auto`: each belongs next to the code.
- **Preferences keys are stable.** A new preference gets a new key with a documented default;
  nothing existing is renamed.

## Testing

- Boringly explicit: setup, execute, verify, in a straight line. Minimal logic inside a test.
- **Deterministic data:** fixed dates and names, never `now()` or random values. Folder listings
  are passed as literal arrays to the pure resolver so the expectation is a literal.
- **Static expectations:** the expected flag list, the expected folder name, the expected JSON are
  literals, never built by the test from the code under test.
- **Beyond the happy path:** an empty folder, a `.part` alone, several candidate files, a name
  that collides, a name that is empty or contains a slash, a rename to the same name, a run with
  no `input` event.
- Test names describe the scenario.
- `swift test` and `go test`. No frameworks added. Nothing needs ffmpeg, whisper-cli, a model,
  audio hardware or the network.

Views are not unit tested; the repo has no view harness and this work adds none. What is testable
is audio resolution, display names, listing and creating and renaming folders, the preference and
its two argument builders, and folding pipeline events into a result.

## Documentation

English, plain verbs, claims calibrated to evidence. `README.md` says what the section does and
where files land; `agent-os/product/roadmap.md` records the phase and the decisions that shaped it,
not the views.
