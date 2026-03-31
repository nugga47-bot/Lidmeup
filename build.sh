#!/bin/bash
# Build Lidmeup macOS app
set -e

echo "Building Lidmeup..."
swift build -c release

BINARY=".build/release/Lidmeup"

if [ -f "$BINARY" ]; then
    echo ""
    echo "Build successful!"
    echo "Run with: $BINARY"
    echo ""
    echo "Or to create an .app bundle:"
    echo "  mkdir -p Lidmeup.app/Contents/MacOS"
    echo "  cp $BINARY Lidmeup.app/Contents/MacOS/"
    echo "  cp Info.plist Lidmeup.app/Contents/"
    echo "  open Lidmeup.app"
else
    echo "Build failed."
    exit 1
fi
