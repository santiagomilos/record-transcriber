# Installable on another Mac (Phase 2.7)

## Context

Record Transcriber only exists on the machine that builds it: `bin/` is gitignored, the bundle is
ad-hoc signed by hand, and there is no remote, no tag and no artifact. The owner wants to hand the
app to a friend who has an Apple Silicon Mac and already uses Claude Code. The original request also
asked for a selectable LLM provider (the friend was thought to use Copilot); that was dropped during
shaping because the friend uses Claude Code too, so `internal/summary` and `claude --print` stay as
they are.

Decisions made during shaping (`/agent-os:shape-spec`):

- Prebuilt `.app` in a `.zip` attached to a **GitHub Release** on a **public** repo
  `github.com/santiagomilos/record-transcriber` (repo not created yet; `gh` not installed).
- Release built **locally** with `make release VERSION=x.y.z`; no CI.
- Friend installs with one `install.sh` that installs Homebrew if missing, the formulae, checks
  Claude Code without signing in, downloads the latest release, installs and launches the app.
- Apple Silicon only, macOS 14.4+. Ad-hoc signing kept; no notarization, no universal binary.
- Rename the Go module to `github.com/santiagomilos/record-transcriber`.
- No visuals. No new UI. `agent-os/standards/index.yml` is empty, so `standards.md` restates the
  repo's own conventions as the previous specs do.

## What it takes (sizing)

| Piece | Effort | Notes |
|---|---|---|
| Makefile `dist` / `release` / `check` + version stamping | ~80 lines of Make | PlistBuddy, ditto, codesign verify, lipo, gh |
| `install.sh` | ~150 lines of bash | 9 functions, Spanish messages, two env overrides for local testing |
| Go module rename | sed over go.mod + 7 files | behavior unchanged |
| `ToolPaths.swift` | 1 string | claude install hint → native installer |
| Docs | README reorder + roadmap Phase 2.7 + tech-stack Distribution | |
| Owner one-time setup | `brew install gh && gh auth login`, `gh repo create --public`, first `make release` | |
| Friend | one terminal command, password for Homebrew, ~10 min (CLT + formulae), 1.6 GB model on first transcription | |

Not fixable without an Apple Developer ID and therefore documented instead: Gatekeeper on a
browser-downloaded zip (macOS 15+ needs System Settings > Privacy & Security > Open Anyway) and TCC
re-prompting for microphone/system audio on every new build.

## Tasks

### Task 1: Save spec documentation

Create `agent-os/specs/2026-09-09-2354-installable-app/` modeled on
`agent-os/specs/2026-09-07-1909-external-files-transcription/`:

- `plan.md`: this plan.
- `shape.md`: scope, the decisions above each with its rejected alternative (compile from source;
  notarized DMG; CI build; private repo; provider selection), context (visuals: none; product
  alignment: Phase 2.7; roadmap line 34 still true).
- `standards.md`: conventions applied to shell and Make: platform tools only (`ditto`, `PlistBuddy`,
  `codesign`, `lipo`, `curl`, `xattr`), fail fast with Spanish messages to the user and English to
  the maintainer, comments carry constraints (why `</dev/tty`, why stamping precedes `codesign`, why
  `pgrep` guards `osascript`), no third-party deps (`shellcheck` optional), deterministic checks.
- `references.md`: `Makefile` `app`/`run`, `app/Resources/Info.plist`,
  `app/Sources/RecordTranscriber/Pipeline/ToolPaths.swift` (`fallbackPaths`, `Tool.claude`),
  `internal/summary/summary.go:207` `claudeArgs` (`--restricted` is why the script probes it),
  `app/spike/build.sh` (shell style), `Views/LibraryView.swift` `MissingToolsView` (renders
  `installCommand`), platform facts verified: `claude auth status` prints JSON with `loggedIn`,
  `claude --version` is non-interactive, native installer is `curl -fsSL https://claude.ai/install.sh | bash`,
  `sort -V` exists on macOS, `/Applications` is admin group-writable, Gatekeeper on 15+.

No `visuals/`.

### Task 2: Rename the Go module

`go.mod` → `module github.com/santiagomilos/record-transcriber`; sed the import prefix in
`cmd/transcribe/main.go`, `cmd/transcribe/main_test.go` and every `internal/**/*.go` that imports a
sibling package. `gofmt -l .` empty, `go build ./... && go test ./...` green.
Commit: `refactor: rename the module to the GitHub owner`.

### Task 3: Makefile, Info.plist, .gitignore

Files: `Makefile`, `app/Resources/Info.plist`, `.gitignore`.

1. `Info.plist`: `CFBundleShortVersionString` → `0.0.0`, `CFBundleVersion` → `0`, with a comment in
   the plist's existing style: placeholders, `make app` stamps them before signing.
2. Makefile variables: `VERSION ?=`, `BUILD := $(shell git rev-list --count HEAD)`,
   `PLIST_VERSION := $(if $(VERSION),$(VERSION),0.0.0)`, `DIST := dist`,
   `ASSET := Record-Transcriber-arm64.zip`, `TAG := v$(VERSION)`,
   `PREV_TAG := $(shell git describe --tags --abbrev=0 2>/dev/null)`,
   `NOTES_RANGE := $(if $(PREV_TAG),$(PREV_TAG)..HEAD,HEAD)`. Extend `.PHONY`.
3. `app` target: between the icon step and `codesign`, stamp with
   `/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(PLIST_VERSION)" -c "Set :CFBundleVersion $(BUILD)" "$(APP)/Contents/Info.plist"`.
   Comment: Info.plist is sealed into the code signature, so the stamp must precede `codesign`.
   PlistBuddy over sed: parses the plist and fails loudly on a missing key.
4. `check` target: `bash -n install.sh`; `shellcheck install.sh` when `command -v shellcheck`
   succeeds, otherwise print "shellcheck not installed, skipped".
5. `dist: check app` — require semver `VERSION` (`grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'`, else
   `usage: make dist VERSION=x.y.z`); `rm -rf dist && mkdir -p dist`;
   `codesign --verify --deep --strict "$(APP)"`; `lipo -archs` on both Mach-Os must be `arm64`;
   `plutil -lint` the plist; `ditto -c -k --keepParent "$(APP)" dist/$(ASSET)`;
   write `dist/notes.md` = install one-liner + `git log --format='- %s' $(NOTES_RANGE)`.
   Comment: fixed asset name so `releases/latest/download/<asset>` resolves forever; `ditto`
   because it is what unpacks on the other side and keeps the signature's resource layout.
6. `release-preflight`: semver; `command -v gh` (hint `brew install gh && gh auth login`);
   `gh auth status`; `git remote get-url origin`; branch is `main`; `git status --porcelain` empty;
   tag absent locally and on origin.
7. `release: release-preflight test dist`:
   `git tag -a "$(TAG)" -m "Record Transcriber $(VERSION)"`, `git push origin main "$(TAG)"`,
   `gh release create "$(TAG)" --verify-tag --title "Record Transcriber $(VERSION)" --notes-file dist/notes.md "dist/$(ASSET)#Record Transcriber $(VERSION) (Apple Silicon)"`.
   Comment: tag before release so a failed `gh` step is rerun by hand without re-tagging; no
   `--generate-notes` because it is PR-based and this repo commits straight to main.
8. `clean` also removes `dist`; `.gitignore` gains `dist/`.

Commit: `build: stamp the version and add dist and release targets`.

### Task 4: `install.sh` (new, 0755, repo root)

`#!/usr/bin/env bash`, `set -euo pipefail`, tab-indented like `app/spike/build.sh`, header comment
stating the contract (installs Homebrew, ffmpeg, whisper-cpp, the app; does not edit shell profiles
or sign in to Claude). Everything in functions, `main "$@"` last so a truncated download is a syntax
error, not a half-run. Spanish strings for the user, English code and comments.

Constants: `REPO=santiagomilos/record-transcriber`, `ASSET=Record-Transcriber-arm64.zip`,
`APP_NAME="Record Transcriber"`, `MIN_MACOS=14.4`, `BREW=/opt/homebrew/bin/brew`.
Env overrides: `RECORD_TRANSCRIBER_ZIP` (local zip, skips download), `RECORD_TRANSCRIBER_DEST`
(default `/Applications`, falling back to `~/Applications` when not writable).

Functions, in call order:

- `say`/`warn`/`die` with `==>` prefix like Homebrew.
- `require_macos`: `sw_vers -productVersion` vs `MIN_MACOS` via `sort -V`.
- `require_arm64`: `uname -m` = `arm64`; if `x86_64` and `sysctl -n sysctl.proc_translated` = 1,
  die asking for a native Terminal (Rosetta would install the Intel Homebrew tree).
- `ensure_homebrew`: if `$BREW` exists, `eval "$($BREW shellenv)"`; else announce the password
  prompt and run the official installer `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty`,
  then `shellenv`. `</dev/tty` is load-bearing: when this script is piped into bash, stdin is the
  pipe and Homebrew's "Press RETURN" read would hit EOF.
- `ensure_formulae`: for `ffmpeg whisper-cpp`, `brew list --versions` or `brew install`; then
  `command -v ffmpeg whisper-cli` or die. `HOMEBREW_NO_ENV_HINTS=1`.
- `check_claude` (never fails): resolve `claude` via PATH or `~/.local/bin/claude`; missing → warn
  with the native installer line and "ejecuta `claude` e inicia sesión"; present → print
  `claude --version`, warn `claude update` if `claude --help` lacks `--restricted`, warn to sign in
  if `claude auth status` lacks `"loggedIn": true`. Never spawns an interactive `claude`.
- `download_app`: `mktemp -d` + `trap` cleanup in `main`; copy `RECORD_TRANSCRIBER_ZIP` or
  `curl -fsSL --retry 3 -o` from `https://github.com/$REPO/releases/latest/download/$ASSET`
  (`-L` required: GitHub redirects to objects.githubusercontent.com).
- `install_app`: `ditto -x -k`; verify `Contents/MacOS/RecordTranscriber` exists; if
  `pgrep -xq RecordTranscriber`, `osascript quit` and wait ≤5 s (the guard matters: `quit app` on
  a stopped app can launch it); `rm -rf` old copy; `ditto` into dest;
  `xattr -dr com.apple.quarantine` (defensive: curl sets none, a browser does);
  `codesign --verify --deep --strict` or die "La app descargada está dañada."
- `launch`: `open` the app; print the installed version (PlistBuddy `Print`), that the icon lives in
  the menu bar, that macOS asks for microphone and system audio on the first recording, and that the
  first transcription downloads 1.6 GB.

Commit: `feat: add install.sh for another Mac`.

### Task 5: `ToolPaths.swift`

`app/Sources/RecordTranscriber/Pipeline/ToolPaths.swift:97` only:
`installCommand: "curl -fsSL https://claude.ai/install.sh | bash"`. No test pins the string;
`MissingToolsView` renders it as selectable monospaced text. Same line `install.sh` prints.

Commit: `fix(app): point the claude install hint at the native installer`.

### Task 6: Documentation

- `README.md`: new leading **Install** section (the one-liner
  `bash -c "$(curl -fsSL https://raw.githubusercontent.com/santiagomilos/record-transcriber/main/install.sh)"`,
  what it installs, the manual zip route with the Gatekeeper paragraph for macOS 15+ and 14, the TCC
  paragraph with `tccutil reset Microphone com.santiagomilos.record-transcriber`, Claude Code
  requirement "2.1 or newer, tested against 2.1.267; `claude --help` must list `--restricted`").
  Current install block becomes **Build from source** (plus the version-placeholder note). New
  **Release** section for the maintainer: `brew install gh && gh auth login` once,
  `gh repo create santiagomilos/record-transcriber --public --source . --remote origin --push` once,
  `make release VERSION=x.y.z`, what preflight checks, how to rerun only `gh release create`.
  Final order: Install / Build from source / The app / Use the CLI / How it works / Test / Release.
- `agent-os/product/tech-stack.md`: a **Distribution** paragraph under Other.
- `agent-os/product/roadmap.md`: reword line 34 (notarization still not done; Phase 2.7 ships
  without it) and add **Phase 2.7: Installable on another Mac — shipped** before Phase 3 with the
  decisions and their reasoning, including that provider selection was dropped.

Commits: `docs: describe installing on another Mac`, `docs: record the installable app spec`.

## Verification (owner's machine, no second Mac)

1. `make test` and `make check` pass.
2. `make dist` without VERSION prints the usage line and fails. `make dist VERSION=0.1.0` builds
   `dist/Record-Transcriber-arm64.zip` and `dist/notes.md`; `plutil -p` on the bundle plist shows
   `0.1.0` and the commit count; `unzip -l` shows `Record Transcriber.app/` at the root;
   `codesign --verify --deep --strict` on an extracted copy is silent.
3. `RECORD_TRANSCRIBER_ZIP=dist/Record-Transcriber-arm64.zip RECORD_TRANSCRIBER_DEST="$HOME/Desktop/rt-test" bash install.sh`
   installs and launches from the scratch folder, reports ffmpeg/whisper-cli present and the Claude
   version signed in, leaves no temp dir; a second run replaces the running copy;
   `RECORD_TRANSCRIBER_ZIP=/nonexistent bash install.sh` exits 1 with the Spanish message.
4. Optional: a fresh macOS user account runs step 3 to exercise `shellenv` and the missing-`claude`
   warning path.
5. `make release VERSION=0.1.0` before `gh` is installed stops at the first preflight with the
   `brew install gh` hint. After `gh repo create` and a real release, the README one-liner on the
   owner's machine downloads from `releases/latest/download/`, replaces `/Applications/Record Transcriber.app`
   and launches; a short recording prompts for permissions, downloads the models, and summarizes.

## Risks

- Homebrew's installer needs an admin password and may install the Command Line Tools (minutes,
  one GUI click); the script announces it. A non-admin account cannot install Homebrew.
- `--restricted` / `--strict-mcp-config` need a recent Claude Code; the script probes `--help`
  rather than parsing versions, and summaries are optional so nothing blocks the install.
- Every ad-hoc build has a new signature: TCC re-prompts; a stale grant can silently deny
  (documented reset command).
- `CFBundleVersion` = commit count is unique only on `main`; preflight enforces `main`.
- `gh release create` failing after the tag is pushed: rerun that command by hand (documented).
- Public repo exposes `agent-os/` and `testdata/README.md`; no media or transcripts are tracked.
- `TEST_FLAGS` in the Makefile stays Command Line Tools specific: out of scope, the friend never builds.
