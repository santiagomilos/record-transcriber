APP_NAME := Record Transcriber
BUNDLE_ID := com.santiagomilos.record-transcriber
APP := bin/$(APP_NAME).app

# The icon is generated from one PNG at build time, so git carries the artwork
# rather than a binary .icns built from it.
ICON_SOURCE := app/Resources/AppIcon.png
ICONSET := app/.build/AppIcon.iconset

# swift-testing ships inside the Command Line Tools but is not on the default
# search paths, so `swift test` has to be pointed at it. Building with Xcode
# installed would not need any of this.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIBRARIES := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
TEST_FLAGS := \
	-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_LIBRARIES)

.PHONY: all transcribe app icon run test test-go test-swift clean

all: app

## transcribe: build the command-line tool
transcribe:
	go build -o bin/transcribe ./cmd/transcribe

## app: build the macOS app bundle, with the CLI embedded and signed ad-hoc
##
## The bundle is assembled by hand rather than by Xcode, and signed ad-hoc
## because this machine has no signing identity. Ad-hoc is enough for the
## microphone and audio-capture permissions, but the signature changes on every
## rebuild, so macOS may ask for them again after one.
app: transcribe
	swift build -c release --package-path app
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp app/.build/release/RecordTranscriber "$(APP)/Contents/MacOS/RecordTranscriber"
	cp bin/transcribe "$(APP)/Contents/Resources/transcribe"
	cp app/Resources/Info.plist "$(APP)/Contents/Info.plist"
	@$(MAKE) --no-print-directory icon
	codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP)"
	@echo "built $(APP)"

## icon: render AppIcon.png into the .icns the bundle needs
##
## The artwork already carries the rounded-square shape and its transparency,
## so it is only scaled — macOS applies no mask of its own to CFBundleIconFile.
icon:
	rm -rf "$(ICONSET)"
	mkdir -p "$(ICONSET)"
	for size in 16 32 128 256 512; do \
		sips -Z $$size "$(ICON_SOURCE)" --out "$(ICONSET)/icon_$${size}x$${size}.png" >/dev/null; \
		sips -Z $$(($$size * 2)) "$(ICON_SOURCE)" --out "$(ICONSET)/icon_$${size}x$${size}@2x.png" >/dev/null; \
	done
	iconutil --convert icns --output "$(APP)/Contents/Resources/AppIcon.icns" "$(ICONSET)"

## run: build and launch the app through LaunchServices
##
## `open` rather than running the executable directly: launching it from a
## terminal makes macOS attribute the permission prompts to the terminal.
run: app
	open "$(APP)"

test: test-go test-swift

test-go:
	go test ./...

test-swift:
	swift test --package-path app $(TEST_FLAGS)

clean:
	rm -rf bin app/.build
