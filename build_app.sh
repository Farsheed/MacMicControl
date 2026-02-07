#!/bin/bash

set -e

echo "Building Mac Mic Control..."
swift build -c release --arch arm64 --arch x86_64

BINARY_NAME="MacMicControl"
APP_DISPLAY_NAME="Mac Mic Control"
APP_BUNDLE="${APP_DISPLAY_NAME}.app"
BINARY_PATH=".build/apple/Products/Release/${BINARY_NAME}"

# Check if universal binary exists, otherwise look for single arch
if [ ! -f "$BINARY_PATH" ]; then
    # Fallback to standard path if universal build puts it elsewhere or fails to merge automatically
    # SPM usually puts universal binaries in .build/apple/Products/Release/ if we use --arch flags
    # But let's check.
    echo "Checking for binary..."
    if [ -f ".build/release/${BINARY_NAME}" ]; then
        BINARY_PATH=".build/release/${BINARY_NAME}"
    fi
fi

echo "Creating App Bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY_PATH}" "${APP_BUNDLE}/Contents/MacOS/"
cp "Info.plist" "${APP_BUNDLE}/Contents/"
if [ -f "images/AppIcon.icns" ]; then
    cp "images/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
fi

echo "Signing..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "Done! App is at ${APP_BUNDLE}"
