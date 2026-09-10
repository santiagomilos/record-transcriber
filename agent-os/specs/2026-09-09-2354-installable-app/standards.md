# Standards for Installable on Another Mac

`agent-os/standards/index.yml` contains no standards, so none were pulled in. What follows are the
conventions the existing code already holds itself to, applied here to a Makefile and a shell
script, which the repo had not needed before.

---

## Shell and Make

- **Platform tools only.** `ditto`, `PlistBuddy`, `codesign`, `lipo`, `plutil`, `curl`, `xattr`,
  `pgrep`, `osascript` all ship with macOS. `gh` is the one addition and is the maintainer's, not
  the friend's. `shellcheck` is used when present and never required.
- **Fail fast, and say so in the user's language.** Every precondition in `install.sh` is checked
  before anything is downloaded or installed, and every failure is one Spanish sentence that says
  what to do. Messages meant for the maintainer (`make dist`, `make release`) are English, like the
  rest of the repo.
- **Everything in functions, `main` last.** A script run through `curl | bash` that is cut short
  must fail to parse rather than run half of itself.
- **Comments say what the reader cannot see.** Why `</dev/tty` on the Homebrew installer, why the
  version stamp precedes `codesign`, why `pgrep` guards `osascript quit`, why the asset name is
  fixed: each lives next to the line it constrains.
- **No hidden side effects.** The installer does not edit `.zprofile` or `.zshrc`, does not sign in
  to anything, and cleans its temp directory on exit.
- **Idempotent.** Running the installer twice installs nothing twice and replaces the app in place,
  quitting the running copy first.

## Versioning and release

- **Derived, not committed.** The bundle's version is stamped at build time from `VERSION` and the
  git commit count; the source plist carries placeholders. Same philosophy as the icon, which git
  carries as a PNG and the build renders.
- **Preflight before any irreversible step.** `make release` refuses to run without `gh`, without
  an `origin`, off `main`, with a dirty tree, or with an existing tag, and only then tags, pushes
  and publishes, in that order, so a failed publish is retried by hand without re-tagging.
- **One fixed asset name.** `Record-Transcriber-arm64.zip`, so the latest-release URL is stable.
- **Conventional Commits, atomic.** The rename, the build changes, the installer, the Swift string
  and the docs are separate commits with their own type.

## Testing

- `make check` parses the installer (`bash -n`) and lints it when `shellcheck` is installed;
  `make dist` depends on it so a release cannot ship a script that does not parse.
- The install path is exercised locally through two environment overrides,
  `RECORD_TRANSCRIBER_ZIP` and `RECORD_TRANSCRIBER_DEST`, before any release exists.
- `make test` stays green: the Go rename and the one-string Swift change touch no behavior.

## Documentation

English, plain verbs, claims calibrated to evidence. `README.md` leads with what a user does,
keeps building from source for developers, and closes with what the maintainer does to release.
`agent-os/product/roadmap.md` records the phase and its decisions; `tech-stack.md` records how the
app is distributed.
