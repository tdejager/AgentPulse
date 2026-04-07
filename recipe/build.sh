#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# Build the app bundle using the same script as local dev
bash build-app.sh release

# Copy the .app bundle to PREFIX
APP_DIR="${PREFIX}/lib/agentpulse"
mkdir -p "${APP_DIR}"
cp -R build/AgentPulse.app "${APP_DIR}/"

# Install menuinst shortcut
mkdir -p "${PREFIX}/Menu"
install -m0644 "${RECIPE_DIR}/menu.json" "${PREFIX}/Menu/${PKG_NAME}_menu.json"
install -m0644 AppIcon.icns "${PREFIX}/Menu/agentpulse.icns"
