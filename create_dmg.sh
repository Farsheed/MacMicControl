#!/bin/bash

set -e

APP_NAME="Mac Mic Control"
DMG_NAME="MacMicControl.dmg"
APP_BUNDLE="${APP_NAME}.app"
TEMP_DIR="dmg_temp"

# Ensure the app exists
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "Error: ${APP_BUNDLE} not found. Please build the app first."
    exit 1
fi

# Clean up previous artifacts
rm -rf "${TEMP_DIR}"
rm -f "${DMG_NAME}"

# Prepare temp directory
echo "Preparing DMG contents..."
mkdir -p "${TEMP_DIR}"
cp -r "${APP_BUNDLE}" "${TEMP_DIR}/"
ln -s /Applications "${TEMP_DIR}/Applications"

# Create DMG
echo "Creating DMG..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${TEMP_DIR}" \
  -ov -format UDZO \
  "${DMG_NAME}"

# Cleanup
echo "Cleaning up..."
rm -rf "${TEMP_DIR}"

echo "Done! DMG created at ${DMG_NAME}"
