# Builds a release .app bundle and ad-hoc signs it.
# Prerequisites: Xcode command-line tools, swift toolchain in PATH.
#
# Targets:
#   make bundle          — release build + assemble Agamon.app in project root
#   make icon            — regenerate packaging/AppIcon.icns from icon.png
#   make clean           — remove Agamon.app and swift build artifacts

.PHONY: bundle icon clean

APP          := Agamon.app
BINARY_SRC   := .build/release/Agamon
BUNDLE_SRC   := .build/release/Agamon_Agamon.bundle
INFO_PLIST   := packaging/Info.plist
ENTITLEMENTS := packaging/Agamon.entitlements
ICON_SRC     := packaging/AppIcon.icns

bundle: _swift_build _assemble _sign
	@echo "✓ $(APP) is ready."

_swift_build:
	swift build -c release

# Assemble the .app directory structure.
# Bundle.module in the app looks for Agamon_Agamon.bundle at Bundle.main.bundleURL
# (i.e. directly inside Agamon.app/, not Contents/), so it goes there — not in Resources.
_assemble: $(INFO_PLIST)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	cp $(BINARY_SRC)  $(APP)/Contents/MacOS/Agamon
	cp $(INFO_PLIST)  $(APP)/Contents/Info.plist
	cp -R $(BUNDLE_SRC) $(APP)/Contents/Resources/
	@if [ -f $(ICON_SRC) ]; then \
		cp $(ICON_SRC) $(APP)/Contents/Resources/AppIcon.icns; \
	else \
		echo "Warning: $(ICON_SRC) not found — run 'make icon' first"; \
	fi

# SIGNING_IDENTITY defaults to ad-hoc for local builds.
# CI sets it to the Developer ID via the SIGNING_IDENTITY env var.
SIGNING_IDENTITY ?= -

_sign:
	codesign --force --deep --sign "$(SIGNING_IDENTITY)" \
		--entitlements $(ENTITLEMENTS) \
		--options runtime \
		$(APP)

icon:
	@bash scripts/generate_icon.sh icon.png

clean:
	rm -rf $(APP) .build
