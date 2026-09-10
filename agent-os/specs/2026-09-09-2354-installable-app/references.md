# References for Installable on Another Mac

## Code in this repo

### The build

- **Location:** `Makefile`, targets `app` and `run`.
- **Relevance:** `app` assembles the bundle by hand and signs it ad-hoc after copying
  `app/Resources/Info.plist` verbatim; the version stamp has to go between the copy and the
  `codesign` line. `run` quits the running app through `osascript` before `open`, which is the
  same sequence `install.sh` needs when replacing an installed copy.

### The bundle's plist

- **Location:** `app/Resources/Info.plist`.
- **Relevance:** carried `0.1.0` / `1` as literals. Now placeholders that `make app` overwrites.
  `LSMinimumSystemVersion` 14.4 is the floor the installer enforces.

### Where the app looks for tools

- **Location:** `app/Sources/RecordTranscriber/Pipeline/ToolPaths.swift`, `fallbackPaths` and
  `Tool.claude`.
- **Relevance:** `/opt/homebrew/bin` and `~/.local/bin` are already in the fallback list, which is
  why the installer does not have to touch the friend's shell profile. `Tool.claude.installCommand`
  is the string the window shows when `claude` is missing; it changes from the npm route to the
  native installer so the app and `install.sh` give the same advice.

### Why the installer probes `--restricted`

- **Location:** `internal/summary/summary.go`, `claudeArgs`.
- **Relevance:** the flags passed to `claude --print` (`--restricted`, `--strict-mcp-config`,
  `--system-prompt`) exist only in recent Claude Code. The installer checks `claude --help` for
  `--restricted` rather than parsing a version number, so the check stays true across releases.

### Shell style

- **Location:** `app/spike/build.sh`.
- **Relevance:** the only shell script in the repo before this work: `set -eu`, tab indentation,
  a header comment that states what the script is for. `install.sh` keeps the voice and adds
  `pipefail` and functions.

### Where the install hint is rendered

- **Location:** `app/Sources/RecordTranscriber/Views/LibraryView.swift`, `MissingToolsView`.
- **Relevance:** renders `installCommand` as selectable monospaced text, so a `curl | bash` line
  fits where `npm install -g ...` did.

### Prior specs, for document shape

- **Location:** `agent-os/specs/2026-09-07-1909-external-files-transcription/`.
- **Relevance:** the `plan.md` / `shape.md` / `standards.md` / `references.md` convention this spec
  follows.

## Platform facts verified for this spec

- On this machine (macOS 26.6.2, Claude Code 2.1.267): `claude --version` prints
  `2.1.267 (Claude Code)` without starting a session; `claude auth status` prints JSON with
  `"loggedIn": true`; `claude --help` lists `--restricted`.
- Claude Code's documented install for macOS is the native installer,
  `curl -fsSL https://claude.ai/install.sh | bash`, which places `claude` under `~/.local/bin` and
  auto-updates; `brew install --cask claude-code` and npm are the alternatives
  (https://code.claude.com/docs/en/setup).
- `/usr/libexec/PlistBuddy`, `/usr/bin/ditto`, `/usr/bin/lipo` and `sort -V` are present on
  macOS without Xcode. `shellcheck` is not.
- Homebrew's installer reads "Press RETURN" from stdin and asks for the password on the terminal;
  when a script is piped into `bash`, stdin is the pipe, so the installer must be given
  `</dev/tty`. Homebrew's own documented one-liner uses the `bash -c "$(curl ...)"` form for the
  same reason.
- GitHub serves `https://github.com/<owner>/<repo>/releases/latest/download/<asset>` for public
  repos with a redirect to `objects.githubusercontent.com`, so `curl -L` is required.
- Gatekeeper on macOS 15 and later no longer honors Control-click > Open for an unsigned or ad-hoc
  signed app that carries the quarantine attribute; the user has to allow it under System
  Settings > Privacy & Security ("Open Anyway"), or the attribute has to be removed with
  `xattr -dr com.apple.quarantine`. `curl` downloads carry no quarantine attribute; browser
  downloads do.
- Microphone and system-audio grants are keyed to the bundle identifier and the code signature,
  so every ad-hoc rebuild prompts again on the first recording.
