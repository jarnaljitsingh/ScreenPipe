#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ScreenPipe"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp Info.plist "$CONTENTS/Info.plist"

# --- Build AppIcon.icns from Resources/icon.png ---
if [ -f "Resources/icon.png" ]; then
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"
    for pair in "16:icon_16x16" "32:icon_16x16@2x" \
                "32:icon_32x32" "64:icon_32x32@2x" \
                "128:icon_128x128" "256:icon_128x128@2x" \
                "256:icon_256x256" "512:icon_256x256@2x" \
                "512:icon_512x512" "1024:icon_512x512@2x"; do
        size="${pair%%:*}"
        name="${pair##*:}"
        sips -z "$size" "$size" Resources/icon.png --out "$ICONSET_DIR/$name.png" >/dev/null
    done
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "Built AppIcon.icns"
fi

ARCH=$(uname -m)
TARGET="${ARCH}-apple-macos13.0"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)

# Collect sources
SOURCES=()
while IFS= read -r -d '' f; do
    SOURCES+=("$f")
done < <(find Sources -name "*.swift" -print0)

echo "Compiling ${#SOURCES[@]} Swift files for $TARGET …"

swiftc "${SOURCES[@]}" \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -O \
    -module-name ScreenPipe \
    -framework AppKit \
    -framework SwiftUI \
    -framework Carbon \
    -o "$MACOS_DIR/$APP_NAME"

# Prefer a real Apple Development identity (stable across rebuilds so TCC
# permissions don't get invalidated). Fall back to ad-hoc if none available.
SIGN_ID=$(security find-identity -v -p codesigning \
    | grep -oE '"Apple Development:[^"]+"' | head -1 | tr -d '"')
if [ -n "$SIGN_ID" ]; then
    echo "Signing with: $SIGN_ID"
    codesign --force --deep --sign "$SIGN_ID" "$APP_BUNDLE"
else
    echo "No Apple Development identity found — ad-hoc signing."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo ""
echo "✔ Built $APP_BUNDLE"
echo ""
echo "Run it with:"
echo "    open \"$APP_BUNDLE\""
echo ""
echo "Or move it to /Applications:"
echo "    mv \"$APP_BUNDLE\" /Applications/"
