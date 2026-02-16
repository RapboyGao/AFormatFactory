#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AFormatFactory"
EXECUTABLE_NAME="AFormatFactory"
BUNDLE_ID="${BUNDLE_ID:-com.albert.aformatfactory}"
APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-1}"

BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICON_FILE="$ROOT_DIR/Assets/AppIcon.icns"
EXECUTABLE_PATH="$BUILD_DIR/$EXECUTABLE_NAME"

mkdir -p "$DIST_DIR" "$ROOT_DIR/Assets"

if [[ ! -f "$ICON_FILE" ]]; then
  echo "[1/5] Generating app icon..."
  rm -rf "$ICONSET_DIR"
  /usr/bin/swift "$ROOT_DIR/Scripts/generate_app_icon.swift" "$ICONSET_DIR"
  /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
fi

echo "[2/5] Building release executable..."
(cd "$ROOT_DIR" && ./Scripts/build_ffmpeg_libs.sh)
(cd "$ROOT_DIR" && swift build -c "$CONFIGURATION")

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Executable not found at: $EXECUTABLE_PATH" >&2
  exit 1
fi

echo "[3/5] Assembling .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"

FFMPEG_BIN_DIR="$RESOURCES_DIR/bin"
FFMPEG_BIN_PATH="$FFMPEG_BIN_DIR/ffmpeg"
mkdir -p "$FFMPEG_BIN_DIR"
if [[ -x "$ROOT_DIR/ThirdParty/ffmpeg-install/bin/ffmpeg" ]]; then
  cp "$ROOT_DIR/ThirdParty/ffmpeg-install/bin/ffmpeg" "$FFMPEG_BIN_PATH"
  chmod +x "$FFMPEG_BIN_PATH"
else
  echo "Missing ffmpeg binary at ThirdParty/ffmpeg-install/bin/ffmpeg" >&2
  echo "Run: ./Scripts/build_ffmpeg_libs.sh ENABLE_PROGRAMS=1" >&2
  exit 1
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [[ "${SIGN_APP:-1}" == "1" ]]; then
  echo "[4/5] Signing app (identity: $SIGN_IDENTITY)..."
  /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
else
  echo "[4/5] Signing skipped (SIGN_APP=0)."
fi

echo "[5/5] Done: $APP_DIR"
if [[ "$OPEN_AFTER_BUILD" == "1" ]]; then
  echo "Opening app..."
  open "$APP_DIR"
else
  echo "Double-click to run, or execute: open \"$APP_DIR\""
fi
