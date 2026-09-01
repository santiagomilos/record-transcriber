#!/bin/sh
# Builds the process-tap spike into an ad-hoc signed .app bundle and launches it
# through LaunchServices, so macOS attributes the permission prompts to the
# bundle rather than to the terminal that started it.
#
# Throwaway alongside main.swift. See
# agent-os/specs/2026-09-01-0255-macos-recording-app/plan.md, Task 2.

set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
app="$root/bin/AudioSpike.app"
identifier="com.santiagomilos.record-transcriber.spike"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

swiftc \
	-O \
	-target arm64-apple-macos14.4 \
	-framework CoreAudio \
	-framework AudioToolbox \
	-framework AVFoundation \
	-framework AppKit \
	-o "$app/Contents/MacOS/AudioSpike" \
	"$root/app/spike/main.swift"

cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>AudioSpike</string>
	<key>CFBundleIdentifier</key>
	<string>$identifier</string>
	<key>CFBundleName</key>
	<string>AudioSpike</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.4</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>Prueba de captura de micrófono para Record Transcriber.</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>Prueba de captura del audio del sistema para Record Transcriber.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier "$identifier" "$app"
codesign --display --verbose=2 "$app" 2>&1 | sed 's/^/  /'

echo "built $app"
