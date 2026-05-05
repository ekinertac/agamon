# Builds a release .app bundle and signs it.
# Prerequisites: Xcode command-line tools, swift toolchain in PATH.
#
# Targets:
#   make bundle          — release build + assemble Agamon.app in project root
#   make icon            — regenerate packaging/AppIcon.icns from icon.png
#   make clean           — remove Agamon.app and swift build artifacts
#
# Sparkle 2 note: Sparkle.framework is a binary SPM dependency. _embed_frameworks copies
# it from .build/artifacts into the app bundle and adds the correct @rpath. Signing must
# happen in order: XPC services → Sparkle.framework → main binary → .app (no --deep).

.PHONY: bundle icon clean

APP          := Agamon.app
BINARY_SRC   := .build/release/Agamon
BUNDLE_SRC   := .build/release/Agamon_Agamon.bundle
INFO_PLIST   := packaging/Info.plist
ENTITLEMENTS := packaging/Agamon.entitlements
ICON_SRC     := packaging/AppIcon.icns

bundle: _swift_build _assemble _embed_frameworks _sign
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

# Copy Sparkle.framework from SPM artifacts into the bundle and fix the rpath.
# SPM links the binary against Sparkle via an artifacts-relative rpath; the bundle
# needs @executable_path/../Frameworks so the framework resolves at runtime.
_embed_frameworks:
	$(eval SPARKLE_FW=$(shell find .build/artifacts -name "Sparkle.framework" -type d 2>/dev/null | head -1))
	@if [ -n "$(SPARKLE_FW)" ]; then \
		echo "Embedding $(SPARKLE_FW)"; \
		mkdir -p "$(APP)/Contents/Frameworks"; \
		cp -R "$(SPARKLE_FW)" "$(APP)/Contents/Frameworks/"; \
		install_name_tool -add_rpath "@executable_path/../Frameworks" "$(APP)/Contents/MacOS/Agamon" 2>/dev/null || true; \
	fi

# SIGNING_IDENTITY defaults to ad-hoc for local builds.
# CI sets it to the Developer ID via the SIGNING_IDENTITY env var.
#
# Signing order matters for Sparkle: XPC services → framework → main app.
# --deep is intentionally absent — it would re-sign already-signed XPC helpers
# with the wrong entitlements, breaking the Sparkle updater on Developer ID builds.
SIGNING_IDENTITY ?= -

_sign:
	@if [ -d "$(APP)/Contents/Frameworks/Sparkle.framework" ]; then \
		find "$(APP)/Contents/Frameworks/Sparkle.framework" \
			\( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" -o -name "fileop" \) \
			-print0 | sort -rz \
			| xargs -0 -I{} codesign --force --sign "$(SIGNING_IDENTITY)" \
				--options runtime --preserve-metadata=entitlements {}; \
		codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime \
			--preserve-metadata=entitlements \
			"$(APP)/Contents/Frameworks/Sparkle.framework"; \
	fi
	codesign --force --sign "$(SIGNING_IDENTITY)" \
		--entitlements $(ENTITLEMENTS) \
		--options runtime \
		$(APP)

icon:
	@bash scripts/generate_icon.sh icon.png

clean:
	rm -rf $(APP) .build
