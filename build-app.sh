#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="AgentPulse"
BUNDLE_DIR="$SCRIPT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

CONFIG="${1:-release}"

echo "Building $APP_NAME ($CONFIG)..."
swift build -c "$CONFIG"

# Determine the built executable path
if [ "$CONFIG" = "release" ]; then
    EXEC_PATH="$SCRIPT_DIR/.build/release/$APP_NAME"
else
    EXEC_PATH="$SCRIPT_DIR/.build/debug/$APP_NAME"
fi

if [ ! -f "$EXEC_PATH" ]; then
    echo "Error: executable not found at $EXEC_PATH"
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy executable
cp "$EXEC_PATH" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy resource bundle if it exists (for TestData)
RESOURCE_BUNDLE="$(dirname "$EXEC_PATH")/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

# Copy app icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Ad-hoc code sign
echo "Code signing..."
codesign --force --sign - "$BUNDLE_DIR"

echo ""
echo "Built: $BUNDLE_DIR"
echo "Run:   open $BUNDLE_DIR"
echo "Mock:  open $BUNDLE_DIR --args --mock"
