# Installable on Another Mac — Shaping Notes

## Scope

Make `Record Transcriber.app` installable on a second Mac by someone who does not build software:
the owner's friend, on Apple Silicon, who already uses Claude Code. Until now the app existed only
where it was built: `bin/` is gitignored, the bundle is ad-hoc signed by hand, there is no remote,
no tag and no artifact.

The deliverable is a release path for the owner (`make release VERSION=x.y.z`, publishing a zip to
a GitHub Release) and an install path for the friend (`install.sh`, one terminal command that
installs the dependencies and the app). The pipeline, the app's behavior and the UI are untouched.

The request started as two things: make the app installable anywhere, and let the user choose the
LLM behind the summaries, because the friend was believed to use Copilot. The second half was
dropped during shaping: the friend uses Claude Code too, so `claude --print` stays the one and only
summary backend. Nothing in `internal/summary` changes.

## Decisions

**A prebuilt app, not a build from source.** The friend gets a `.zip` with the bundle inside.
Compiling from source was the cheaper option for this repo and the more expensive one for the
friend: it needs Go 1.27 and a Swift 6 toolchain, neither of which a non-developer has. A
notarized DMG was rejected because it needs an Apple Developer Program membership (99 USD a year)
and a signing identity; the roadmap already ruled notarization out and this work does not reverse
that. Ad-hoc signing stays, which has two consequences documented rather than fixed: a
browser-downloaded copy is blocked by Gatekeeper until the user allows it, and macOS asks for the
microphone and system-audio permissions again after every new build, because the signature they
were granted to has changed.

**Apple Silicon only.** The friend's Mac is Apple Silicon, so the build stays thin arm64 as it is
today. A universal binary was the alternative and would have covered Intel at the cost of a `lipo`
step and a whisper that runs without Metal; nobody asked for it.

**GitHub Release on a public repo, built locally.** The zip is attached to a release under a fixed
asset name, so `releases/latest/download/Record-Transcriber-arm64.zip` always resolves to the
newest one and the installer never needs the GitHub API. Sending the zip by hand (AirDrop, Drive)
was the first proposal and the owner chose GitHub instead. A private repo was rejected because the
friend would need `gh auth login` as a collaborator to download anything; the code has no secrets,
and nothing but the bundle identifier is personal. The release is built on the owner's machine by
`make release`, not by GitHub Actions: the binary that ships is the one already tested here, and
there is no CI environment to debug where the runner's Swift and the Makefile's Command Line Tools
assumptions differ. CI stays possible later.

**One installer script, and it installs Homebrew.** `install.sh` checks macOS 14.4+ and arm64,
installs Homebrew when missing, installs `ffmpeg` and `whisper-cpp`, downloads the latest release,
replaces the app in `/Applications`, strips the quarantine flag and launches it. Stopping to ask
the friend to install Homebrew first was the alternative; one command was the point. The script
does not edit shell profiles: the app finds `/opt/homebrew/bin` through `ToolPaths.fallbackPaths`
on its own.

**Claude Code is checked, never installed or signed in.** Summaries are optional in the app, so a
missing `claude` is a warning with the native installer line, not a failure. The script prints
`claude --version`, probes `claude --help` for `--restricted` (the flag `summary.go` depends on,
which older versions lack) and `claude auth status` for `loggedIn`, and warns in each case. It
never launches an interactive `claude`, because signing in opens a browser and belongs to the
user.

**The version comes from the tag, not from the source.** `Info.plist` in git carries placeholders
(`0.0.0`, build `0`); `make app` stamps `VERSION` and the commit count into the copied plist before
signing, because the plist is sealed into the code signature. Keeping the real version in the
source plist was rejected: it is a second place to bump and `make release` would have to commit.

**The Go module is renamed to the GitHub owner.** `github.com/santi/record-transcriber` becomes
`github.com/santiagomilos/record-transcriber` in a separate `refactor` commit. Nobody will
`go install` it, but a public repo whose module path names a different GitHub user is a mistake
waiting to be found.

## Context

- **Visuals:** none. No UI changes.
- **References:** see `references.md`.
- **Product alignment:** Phase 2.7 of `agent-os/product/roadmap.md`. The line that says notarized
  distribution is deliberately not done stays true.

## Standards Applied

`agent-os/standards/index.yml` is empty, so no standards were pulled in. `standards.md` records the
conventions the repo holds itself to, applied to shell and Make for the first time.
