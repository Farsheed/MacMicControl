#!/bin/bash
set -e

APP_NAME="Mac Mic Control"
EXECUTABLE_NAME="MacMicControl"

# Function to build and package for a specific architecture
build_and_package() {
    ARCH=$1
    DMG_SUFFIX=$2
    
    echo "================================================"
    echo "Packaging for $DMG_SUFFIX ($ARCH)..."
    echo "================================================"

    # Assuming builds are already done manually to avoid sandbox issues
    # BIN_PATH=$(swift build -c release --arch "$ARCH" --show-bin-path)
    BIN_PATH=".build/${ARCH}-apple-macosx/release"
    BINARY="$BIN_PATH/$EXECUTABLE_NAME"
    
    if [ ! -f "$BINARY" ]; then
        echo "Error: Binary not found at $BINARY"
        echo "Please run: swift build -c release --arch $ARCH"
        exit 1
    fi

    APP_BUNDLE="${APP_NAME}.app"
    TEMP_DIR="temp_${ARCH}"
    DMG_NAME="MacMicControl_macOS_${DMG_SUFFIX}.dmg"

    # Clean previous temp
    rm -rf "$TEMP_DIR"
    rm -f "$DMG_NAME"
    
    # Create Structure
    APP_DIR="$TEMP_DIR/$APP_BUNDLE"
    mkdir -p "$APP_DIR/Contents/MacOS"
    mkdir -p "$APP_DIR/Contents/Resources"

    # Copy files
    cp "$BINARY" "$APP_DIR/Contents/MacOS/"
    cp "Info.plist" "$APP_DIR/Contents/"
    if [ -f "images/AppIcon.icns" ]; then
        cp "images/AppIcon.icns" "$APP_DIR/Contents/Resources/"
    fi

    # Clean detritus (resource forks, xattrs)
    echo "Cleaning detritus..."
    xattr -cr "$APP_DIR"

    # Sign
    echo "Signing app bundle..."
    codesign --force --deep --sign - "$APP_DIR"

    # Prepare for DMG
    ln -s /Applications "$TEMP_DIR/Applications"

    # Create DMG
    echo "Creating DMG: $DMG_NAME"
    hdiutil create \
      -volname "${APP_NAME}" \
      -srcfolder "$TEMP_DIR" \
      -ov -format UDZO \
      "$DMG_NAME"

    # Cleanup
    rm -rf "$TEMP_DIR"
    
    echo "✅ Finished $DMG_NAME"
}

# Build for Apple Silicon (arm64)
build_and_package "arm64" "AppleSilicon"

# Build for Intel (x86_64)
build_and_package "x86_64" "Intel"

echo "================================================"
echo "Build Summary:"
ls -lh MacMicControl_macOS_*.dmg
echo "================================================"
