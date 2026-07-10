# Fadeo build wrapper. Picks a full Xcode automatically (falls back to Xcode-beta).
DEVELOPER_DIR ?= $(shell [ -d /Applications/Xcode.app ] && echo /Applications/Xcode.app/Contents/Developer || echo /Applications/Xcode-beta.app/Contents/Developer)
export DEVELOPER_DIR

# Some shells export CC/CXX pointing at Homebrew gcc, which SwiftPM's C-target builds
# (e.g. Yams' CYaml shim) pick up instead of clang — gcc chokes on clang-only flags
# xcodebuild passes. Force clang for this build only; doesn't touch your shell profile.
CC := $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang
CXX := $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++
export CC
export CXX

SCHEME  := Fadeo
CONFIG  := Debug
DERIVED := build
APP     := $(DERIVED)/Build/Products/$(CONFIG)/Fadeo.app

.PHONY: all gen icon build run test clean relaunch

all: build

gen: icon
	xcodegen generate

icon:
	@./scripts/make-assets.sh

build: gen
	xcodebuild -project Fadeo.xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS' build

run: build
	@echo "Launching $(APP)"
	@open "$(APP)"

# Install to ~/Applications (no admin, Spotlight-indexed) so you can launch it like a
# normal app while developing. Release installs go to /Applications via the DMG.
install: build
	@pkill -x Fadeo 2>/dev/null || true
	@mkdir -p "$$HOME/Applications"
	@rm -rf "$$HOME/Applications/Fadeo.app"
	@cp -R "$(APP)" "$$HOME/Applications/Fadeo.app"
	@mdimport "$$HOME/Applications/Fadeo.app" 2>/dev/null || true
	@open "$$HOME/Applications/Fadeo.app"
	@echo "installed → ~/Applications/Fadeo.app (searchable in Spotlight)"

relaunch:
	@pkill -x Fadeo || true
	@$(MAKE) run

test:
	xcrun swift test --package-path Packages/FadeoCore

clean:
	rm -rf $(DERIVED) Fadeo.xcodeproj
