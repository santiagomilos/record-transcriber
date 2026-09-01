# Menu Bar Panel Redesign — Shaping Notes

## Scope

Rebuild the menu bar panel of `Record Transcriber.app` from three stock SwiftUI buttons into
a worked panel: a branded header, a primary record control that states what it captures, live
recording and transcription state, and a list of recent recordings with real metadata. Extend
the same design system to the `Grabaciones` window, and make the menu bar icon report state on
its own.

The pipeline, the recorder and the CLI are untouched. This is a presentation change plus the
metadata the new rows need.

## Decisions

**A full panel, not a polish pass.** The reference is the JetBrains Toolbox menu bar panel:
header with brand and actions, grouped cards, and a list of items carrying their own status.
The alternative considered was keeping the three existing items and only fixing typography and
spacing; it was rejected because the complaint was that the panel reads as a prototype, and a
prototype with better spacing is still a prototype.

**A dark palette of its own, not the system appearance.** The panel and the window commit to a
palette sampled from the Toolbox reference rather than following Light and Dark Mode. This buys
the identity; the cost is a theme maintained by hand and a panel that stays dark when the system
is light. Native materials with the user's accent color would have aged better and cost nothing
to maintain, and were the explicit alternative on the table.

**Duration comes from a `meta.json` sidecar.** The rows show duration, and no such data exists
today: the only metadata is which files are present in the session folder. The audio is Ogg/Opus,
which AVFoundation cannot read, so the alternative was an `ffprobe` subprocess per session on
every panel open. The sidecar is written once when a recording ends and read instantly after,
and it also captures the detected language and the segment count, both of which
`PipelineEvent` already carries and `TranscribeRunner.apply` currently discards. Recordings made
before this change show no duration; that is accepted rather than backfilled.

The sidecar does not contradict "the folder on disk is the source of truth" — it is another file
in the folder, and a session whose sidecar is missing or malformed still lists, just without
duration.

**Clicking a recent row opens the window.** The panel is a launcher, as Toolbox is. Expanding a
row inline with quick actions was considered and left out to keep the panel one screen tall.

**The app becomes an accessory (`LSUIElement`).** It lives only in the menu bar, with no Dock
icon and no ⌘Tab entry, which is what a menu bar app is. The consequence to handle is that an
accessory app does not come to the front on its own: opening the library window or Preferences
has to activate the app explicitly.

**The icon animates.** Recording pulses and shows the elapsed time next to the symbol;
transcribing animates. State is then legible without opening anything — which is the reason the
icon carries state at all, per the comment already in `RecordTranscriberApp.swift`.

## Context

- **Visuals:** `visuals/current-panel.png` (the panel as it stands) and
  `visuals/toolbox-reference.png` (JetBrains Toolbox, the target).
- **References:** see `references.md`.
- **Product alignment:** Phase 2 of `agent-os/product/roadmap.md` is shipped and this is work on
  top of it, not a new phase. It stays inside the stated constraints: no third-party packages, no
  Xcode project, ad-hoc signed for personal use.

## Standards Applied

`agent-os/standards/index.yml` is empty, so no standards were pulled in. `standards.md` records
the conventions the existing code holds itself to, which this work continues.
