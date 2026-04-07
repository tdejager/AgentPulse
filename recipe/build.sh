#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# Build the Swift project
swift build -c release

# Create the .app bundle
APP_DIR="${PREFIX}/lib/agentpulse/AgentPulse.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
install -m0755 .build/release/AgentPulse "${MACOS_DIR}/AgentPulse"

# Copy Info.plist
install -m0644 Info.plist "${CONTENTS_DIR}/Info.plist"

# Generate and copy icon
bash scripts/generate-icon.sh
if [ -f AppIcon.icns ]; then
    install -m0644 AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi

# Ad-hoc code sign
codesign --force --sign - "${APP_DIR}"

# Install menuinst shortcut
mkdir -p "${PREFIX}/Menu"
install -m0644 "${RECIPE_DIR}/menu.json" "${PREFIX}/Menu/${PKG_NAME}_menu.json"
install -m0644 AppIcon.icns "${PREFIX}/Menu/agentpulse.icns"
