APP_NAME := Record Transcriber
BUNDLE_ID := com.santiagomilos.record-transcriber
APP := bin/$(APP_NAME).app

# The version lives in the git tag, not in the source plist: `make dist
# VERSION=x.y.z` stamps it into the bundle, and a plain `make app` reads 0.0.0.
# The build number is the commit count, which only `main` is released from.
VERSION ?=
BUILD := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
PLIST_VERSION := $(if $(VERSION),$(VERSION),0.0.0)
TAG := v$(VERSION)

# One fixed asset name, so the installer's
# releases/latest/download/$(ASSET) URL resolves for every release.
DIST := dist
ASSET := Record-Transcriber-arm64.zip
REPO := santiagomilos/record-transcriber
PREV_TAG := $(shell git describe --tags --abbrev=0 2>/dev/null)
NOTES_RANGE := $(if $(PREV_TAG),$(PREV_TAG)..HEAD,HEAD)

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

.PHONY: all transcribe app icon run test test-go test-swift check dist release-preflight release clean

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
	/usr/libexec/PlistBuddy \
		-c "Set :CFBundleShortVersionString $(PLIST_VERSION)" \
		-c "Set :CFBundleVersion $(BUILD)" \
		"$(APP)/Contents/Info.plist"
	codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP)"
	@echo "built $(APP) $(PLIST_VERSION) ($(BUILD))"

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
##
## Quitting first is what makes this show the build that was just made: `open`
## on an app that is already running only brings it to the front, so a rebuild
## keeps displaying the old binary. The app is a menu bar accessory with no
## window of its own, which makes that easy to miss. Failure is ignored because
## nothing running is the normal case.
run: app
	-osascript -e 'quit app "Record Transcriber"' 2>/dev/null
	open "$(APP)"

test: test-go test-swift

test-go:
	go test ./...

test-swift:
	swift test --package-path app $(TEST_FLAGS)

## check: make sure the installer at least parses; lint it when shellcheck is around
check:
	bash -n install.sh
	@if command -v shellcheck >/dev/null; then shellcheck install.sh; else echo "shellcheck not installed, skipped"; fi

## dist: build the release zip for VERSION and the notes that go with it
##
## The zip is made with ditto because that is what unpacks it on the other
## machine, and it keeps the layout the code signature was computed over.
## The checks before it catch the two things that would fail silently on the
## friend's Mac: a broken signature and a binary for the wrong architecture.
dist: check
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "usage: make dist VERSION=x.y.z"; exit 1; }
	@$(MAKE) --no-print-directory app VERSION=$(VERSION)
	codesign --verify --deep --strict "$(APP)"
	lipo -archs "$(APP)/Contents/MacOS/RecordTranscriber" | grep -qx arm64
	lipo -archs "$(APP)/Contents/Resources/transcribe" | grep -qx arm64
	plutil -lint "$(APP)/Contents/Info.plist"
	rm -rf "$(DIST)"
	mkdir -p "$(DIST)"
	ditto -c -k --keepParent "$(APP)" "$(DIST)/$(ASSET)"
	printf 'Install or update with:\n\n```sh\nbash -c "$$(curl -fsSL https://raw.githubusercontent.com/$(REPO)/main/install.sh)"\n```\n\n' > "$(DIST)/notes.md"
	git log --format='- %s' $(NOTES_RANGE) >> "$(DIST)/notes.md"
	@echo "built $(DIST)/$(ASSET)"

## release-preflight: refuse to release from anything but a clean, pushed main
release-preflight:
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "usage: make release VERSION=x.y.z"; exit 1; }
	@command -v gh >/dev/null || { echo "gh is not installed: brew install gh && gh auth login"; exit 1; }
	@gh auth status >/dev/null 2>&1 || { echo "gh is not signed in: gh auth login"; exit 1; }
	@git remote get-url origin >/dev/null 2>&1 || { echo "no origin: gh repo create $(REPO) --public --source . --remote origin --push"; exit 1; }
	@test "$$(git branch --show-current)" = main || { echo "releases are cut from main"; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "the working tree is not clean"; exit 1; }
	@! git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null || { echo "$(TAG) already exists"; exit 1; }
	@! git ls-remote --exit-code --tags origin "refs/tags/$(TAG)" >/dev/null 2>&1 || { echo "$(TAG) already exists on origin"; exit 1; }

## release: tag VERSION, push it, and publish the zip as a GitHub Release
##
## Tag first, publish second: the tag is the fact and the release is its
## announcement, so if `gh` fails the last line is rerun by hand without
## re-tagging. Notes come from the commit subjects since the previous tag
## rather than --generate-notes, which is built from pull requests and this
## repo commits straight to main.
release: release-preflight test dist
	git tag -a "$(TAG)" -m "$(APP_NAME) $(VERSION)"
	git push origin main "$(TAG)"
	gh release create "$(TAG)" \
		--verify-tag \
		--title "$(APP_NAME) $(VERSION)" \
		--notes-file "$(DIST)/notes.md" \
		"$(DIST)/$(ASSET)#$(APP_NAME) $(VERSION) (Apple Silicon)"

clean:
	rm -rf bin app/.build "$(DIST)"
