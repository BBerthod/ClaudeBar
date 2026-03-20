.PHONY: build release app run install uninstall clean update

# Development build
build:
	swift build

# Optimized release build
release:
	swift build -c release

# Create .app bundle
app: release
	@echo "Bundling ClaudeBar.app..."
	@rm -rf build/ClaudeBar.app
	@mkdir -p build/ClaudeBar.app/Contents/MacOS
	@mkdir -p build/ClaudeBar.app/Contents/Resources
	@cp .build/release/ClaudeBar build/ClaudeBar.app/Contents/MacOS/
	@/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.billyberthod.claudebar" \
		-c "Add :CFBundleName string ClaudeBar" \
		-c "Add :CFBundleDisplayName string ClaudeBar" \
		-c "Add :CFBundleVersion string 1.0.0" \
		-c "Add :CFBundleShortVersionString string 1.0.0" \
		-c "Add :CFBundlePackageType string APPL" \
		-c "Add :CFBundleExecutable string ClaudeBar" \
		-c "Add :LSUIElement bool true" \
		-c "Add :LSMinimumSystemVersion string 14.0" \
		-c "Add :NSHighResolutionCapable bool true" \
		build/ClaudeBar.app/Contents/Info.plist
	@echo "✓ build/ClaudeBar.app created"

# Dev mode
run: build
	.build/debug/ClaudeBar

# Install to /Applications (kills running instance first)
install: app
	@echo "Installing to /Applications..."
	@pkill -x ClaudeBar 2>/dev/null || true
	@sleep 1
	@rm -rf /Applications/ClaudeBar.app
	@cp -R build/ClaudeBar.app /Applications/
	@echo "✓ Installed to /Applications/ClaudeBar.app"
	@echo "  Launch: open /Applications/ClaudeBar.app"

# Uninstall
uninstall:
	@pkill -x ClaudeBar 2>/dev/null || true
	@rm -rf /Applications/ClaudeBar.app
	@echo "✓ Uninstalled"

# Update (git pull + reinstall)
update:
	@echo "Updating ClaudeBar..."
	@git pull --rebase origin main
	@$(MAKE) install
	@open /Applications/ClaudeBar.app
	@echo "✓ Updated and relaunched"

# Clean
clean:
	swift package clean
	rm -rf build/
