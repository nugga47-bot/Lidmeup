#!/bin/bash
set -e

APP_NAME="Lidmeup"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"
BINARY_PATH="$(cd "$(dirname "$0")" && pwd)/.build/release/$APP_NAME"

echo "=== Packaging $APP_NAME ==="

# Step 1: Build release binary
echo "[1/3] Building release binary..."
swift build -c release

# Step 2: Generate app icon
echo "[2/3] Generating app icon..."
swift Scripts/generate_icon.swift "/tmp/$APP_NAME.icns"

# Step 3: Create .app bundle
echo "[3/3] Creating $APP_BUNDLE..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Create a launcher script that runs the binary directly.
# This inherits Terminal's Input Monitoring permission, which
# allows HID access without needing a separate TCC entry.
cat > "$APP_BUNDLE/Contents/MacOS/$APP_NAME" << LAUNCHER
#!/bin/bash
exec "$BINARY_PATH"
LAUNCHER
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy icon
cp "/tmp/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Lidmeup</string>
    <key>CFBundleDisplayName</key>
    <string>Lidmeup</string>
    <key>CFBundleIdentifier</key>
    <string>com.lidmeup.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Lidmeup</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Sign it
codesign --force --sign - --deep "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "=== Done! ==="
echo ""
echo "Your app is ready: $(pwd)/$APP_BUNDLE"
echo ""
echo "To open it now:"
echo "  open $APP_BUNDLE"
echo ""
echo "To install to Applications:"
echo "  cp -r $APP_BUNDLE /Applications/"
