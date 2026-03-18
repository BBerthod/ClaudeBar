.PHONY: build release app run clean

build:
	swift build

release:
	swift build -c release

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
		build/ClaudeBar.app/Contents/Info.plist
	@echo "Done: build/ClaudeBar.app"

run: build
	.build/debug/ClaudeBar

install: app
	@echo "Installing to /Applications..."
	@cp -R build/ClaudeBar.app /Applications/
	@echo "Installed: /Applications/ClaudeBar.app"

clean:
	swift package clean
	rm -rf build/
