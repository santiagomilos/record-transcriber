# Summary Text Size and Highlights — Shaping Notes

## Scope

Two changes to how a summary reads in the app's detail view. The owner can make the summary text
larger or smaller, and can mark passages with a highlighter whose marks are still there after the
app is closed. The transcript tab, the pipeline and `transcript.summary.md` itself are untouched.

## Decisions

**A highlighter in four colors, not an underline.** Yellow, green, pink and blue backgrounds, light
enough in opacity that the panel's light text stays readable on the fixed dark palette. A literal
underline and a single-color highlighter were offered; the owner chose several colors.

**Applied from the context menu.** Select text, right-click, `Resaltar ▸ <color>`; `Quitar
resaltado` appears when the selection touches a mark. A color bar next to the tabs was rejected as
UI that is always on screen for an action taken occasionally.

**Saved beside the summary, not inside it.** Marks live in `transcript.summary.highlights.json` in
the session folder, so the session stays self-contained (copy the folder and the marks travel) and
the markdown `claude` wrote is never rewritten. Writing `==text==` into the `.md` was rejected: it
mutates a generated file and the syntax is not part of the markdown the app renders.

The `transcript.` prefix is not cosmetic. `Session.audioFile(among:)` takes the first unknown file
in an import's folder as its recording, and only names under `transcript.` are excluded wholesale.

**A regenerated summary starts clean.** The file records the SHA-256 of the summary it was made
against; when the summary changes, by Resumir de nuevo, Transcribir de nuevo or the CLI, the marks
no longer load. Re-anchoring marks by searching for their text in the new summary was offered and
declined as complexity for a rare case.

**Text size is one global setting for the summary.** A− / A+ beside the tabs and ⌘+ / ⌘−, stored in
UserDefaults, 10 to 24 pt, 12 by default (today's body size). Headings keep their proportion to the
body. Per-session sizes and sharing the size with the transcript tab were offered and declined.

**The summary moves to `NSTextView`.** The app targets macOS 14.4. SwiftUI `Text` with text
selection enabled never tells the app what is selected, and `TextEditor` bound to an attributed
string with a selection only exists from macOS 26. Highlighting needs the selected range, so the
summary is rendered into one `NSAttributedString` and shown in a read-only `NSTextView`.
`MarkdownText.Block.parse` stays the markdown splitter.

Mark offsets are UTF-16 offsets into that rendered string, and each mark also stores its text: a
future renderer change that shifts offsets drops the affected marks instead of misplacing them.

## Context

- **Visuals:** none.
- **References:** see `references.md`.
- **Product alignment:** a reading improvement inside Phase 2's app. The product docs set no
  constraint beyond local-only files and no third-party packages, both kept (CryptoKit and AppKit
  ship with macOS).

## Standards Applied

`agent-os/standards/index.yml` is empty, so no standards were pulled in. `standards.md` records the
conventions the app code already holds itself to.
