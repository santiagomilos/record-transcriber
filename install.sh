#!/usr/bin/env bash
# Installs Record Transcriber on an Apple Silicon Mac: Homebrew if it is
# missing, ffmpeg and whisper-cpp, and the latest release of the app into
# /Applications. It checks Claude Code but never installs it or signs in, and
# it never edits shell profiles: the app finds /opt/homebrew/bin on its own.
#
# Run it as
#     bash -c "$(curl -fsSL https://raw.githubusercontent.com/santiagomilos/record-transcriber/main/install.sh)"
#
# Overrides, for testing before a release exists:
#     RECORD_TRANSCRIBER_ZIP   local zip to install instead of downloading
#     RECORD_TRANSCRIBER_DEST  folder to install into (default /Applications)
#
# Everything lives in functions and main runs last, so a download cut short
# fails to parse instead of running half of the script.

set -euo pipefail

readonly REPO="santiagomilos/record-transcriber"
readonly ASSET="Record-Transcriber-arm64.zip"
readonly APP_NAME="Record Transcriber"
readonly MIN_MACOS="14.4"
readonly BREW="/opt/homebrew/bin/brew"
readonly CLAUDE_INSTALL='curl -fsSL https://claude.ai/install.sh | bash'

# Script-level rather than local to main: the EXIT trap runs after main has
# returned, when its locals are gone and `set -u` would abort the cleanup.
tmpdir=""
installed_app=""

say() { printf '==> %s\n' "$*"; }
warn() { printf '==> Aviso: %s\n' "$*" >&2; }
die() { printf '==> Error: %s\n' "$*" >&2; exit 1; }

require_macos() {
	[[ "$(uname -s)" == Darwin ]] || die "Este instalador es solo para macOS."
	local have lowest
	have=$(sw_vers -productVersion)
	lowest=$(printf '%s\n%s\n' "$MIN_MACOS" "$have" | sort -V | head -n 1)
	[[ "$lowest" == "$MIN_MACOS" ]] || die "$APP_NAME necesita macOS $MIN_MACOS o posterior (tienes $have)."
}

require_arm64() {
	case "$(uname -m)" in
	arm64) return ;;
	x86_64)
		# A terminal running under Rosetta reports x86_64 on an Apple Silicon
		# Mac, and Homebrew would then install its Intel tree under /usr/local.
		if [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" == 1 ]]; then
			die "Esta terminal corre bajo Rosetta. Abre una Terminal nativa y vuelve a ejecutar el instalador."
		fi
		;;
	esac
	die "Solo hay versión para Mac con chip Apple (M1 o posterior)."
}

ensure_homebrew() {
	if [[ ! -x "$BREW" ]]; then
		say "Se instalará Homebrew. Te pedirá tu contraseña de macOS y confirmar con Enter."
		# When this script is itself piped into bash, stdin is the pipe, and the
		# installer's "Press RETURN" read would hit EOF: give it the terminal.
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
		[[ -x "$BREW" ]] || die "Homebrew no quedó instalado en $BREW."
	fi
	eval "$("$BREW" shellenv)"
	say "Homebrew listo."
}

ensure_formulae() {
	export HOMEBREW_NO_ENV_HINTS=1
	local formula
	for formula in ffmpeg whisper-cpp; do
		# `list` first: `install` on a present formula still runs an update.
		if brew list --versions "$formula" >/dev/null 2>&1; then
			say "$formula ya está instalado."
		else
			say "Instalando $formula…"
			brew install "$formula"
		fi
	done
	command -v ffmpeg >/dev/null || die "ffmpeg no aparece en el PATH después de instalarlo."
	command -v whisper-cli >/dev/null || die "whisper-cli no aparece en el PATH después de instalar whisper-cpp."
}

# Summaries are optional in the app, so nothing here fails: it reports.
check_claude() {
	local claude
	if command -v claude >/dev/null; then
		claude=$(command -v claude)
	elif [[ -x "$HOME/.local/bin/claude" ]]; then
		# Where the native installer puts it; a fresh .zshrc may not export it yet.
		claude="$HOME/.local/bin/claude"
	else
		warn "Claude Code no está instalado, así que los resúmenes quedarán desactivados."
		warn "Para tenerlos: $CLAUDE_INSTALL, luego ejecuta 'claude' e inicia sesión."
		return
	fi
	say "Claude Code $("$claude" --version 2>/dev/null || echo "instalado")"
	# The app passes --restricted to `claude --print`; older versions lack it.
	if ! "$claude" --help 2>/dev/null | grep -q -- '--restricted'; then
		warn "Tu Claude Code es anterior al que la app necesita. Actualízalo con: claude update"
	fi
	if ! "$claude" auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
		warn "Claude Code no tiene sesión iniciada. Ejecuta 'claude' en una terminal e inicia sesión para tener resúmenes."
	fi
}

download_app() {
	local zip="$1"
	if [[ -n "${RECORD_TRANSCRIBER_ZIP:-}" ]]; then
		say "Usando $RECORD_TRANSCRIBER_ZIP"
		cp "$RECORD_TRANSCRIBER_ZIP" "$zip" 2>/dev/null || die "No existe $RECORD_TRANSCRIBER_ZIP."
	else
		say "Descargando la última versión de $APP_NAME…"
		# -L: GitHub answers with a redirect to objects.githubusercontent.com.
		curl -fsSL --retry 3 -o "$zip" "https://github.com/$REPO/releases/latest/download/$ASSET" \
			|| die "No se pudo descargar la última versión."
	fi
	[[ -s "$zip" ]] || die "No se pudo descargar la última versión."
}

install_app() {
	local zip="$1" tmp="$2"
	local app="$APP_NAME.app"
	ditto -x -k "$zip" "$tmp/unpacked"
	[[ -x "$tmp/unpacked/$app/Contents/MacOS/RecordTranscriber" ]] || die "El archivo descargado no contiene la app."

	local dest
	if [[ -n "${RECORD_TRANSCRIBER_DEST:-}" ]]; then
		dest="$RECORD_TRANSCRIBER_DEST"
		mkdir -p "$dest"
	elif [[ -w /Applications ]]; then
		dest=/Applications
	else
		dest="$HOME/Applications"
		mkdir -p "$dest"
		say "Sin permiso para escribir en /Applications; se instalará en $dest."
	fi

	# `quit app` on an app that is not running can launch it, hence the guard.
	if pgrep -xq RecordTranscriber; then
		say "Cerrando la copia que está abierta…"
		osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
		local i
		for i in 1 2 3 4 5; do
			pgrep -xq RecordTranscriber || break
			sleep 1
		done
	fi

	rm -rf "$dest/$app"
	ditto "$tmp/unpacked/$app" "$dest/$app"
	# curl sets no quarantine flag, but a browser download of the same zip
	# does, and macOS 15 then refuses to open an ad-hoc signed app.
	xattr -dr com.apple.quarantine "$dest/$app" 2>/dev/null || true
	codesign --verify --deep --strict "$dest/$app" || die "La app descargada está dañada."
	installed_app="$dest/$app"
}

launch() {
	local version
	version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_app/Contents/Info.plist")
	open "$installed_app"
	say "$APP_NAME $version instalado en $installed_app y abierto."
	say "Vive en la barra de menús, no en el Dock. En la primera grabación macOS pedirá permiso de micrófono y de audio del sistema."
	say "La primera transcripción descarga el modelo (1,6 GB) y puede tardar varios minutos."
}

main() {
	require_macos
	require_arm64
	ensure_homebrew
	ensure_formulae
	check_claude

	tmpdir=$(mktemp -d)
	trap 'rm -rf "$tmpdir"' EXIT
	download_app "$tmpdir/$ASSET"
	install_app "$tmpdir/$ASSET" "$tmpdir"
	launch
}

main "$@"
