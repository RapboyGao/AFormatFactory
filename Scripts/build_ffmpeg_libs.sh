#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_SRC_DIR="$ROOT_DIR/ThirdParty/ffmpeg/source"
FFMPEG_BUILD_DIR="$ROOT_DIR/ThirdParty/ffmpeg-build"
FFMPEG_INSTALL_DIR="$ROOT_DIR/ThirdParty/ffmpeg-install"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
ENABLE_PROGRAMS="${ENABLE_PROGRAMS:-0}"
SKIP_FFMPEG_BUILD="${SKIP_FFMPEG_BUILD:-0}"
SIGNATURE_FILE="$FFMPEG_INSTALL_DIR/.build_signature"

if [[ ! -d "$FFMPEG_SRC_DIR/.git" ]]; then
  echo "FFmpeg source not found, syncing..."
  "$ROOT_DIR/Scripts/sync_ffmpeg_source.sh"
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  echo "Unsupported architecture: $ARCH" >&2
  exit 1
fi

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
CC="$(xcrun --sdk macosx --find clang)"

PROGRAM_FLAGS=(--disable-programs)
if [[ "$ENABLE_PROGRAMS" == "1" ]]; then
  PROGRAM_FLAGS=(--enable-ffmpeg --disable-ffplay --disable-ffprobe)
fi

required_artifacts_ready() {
  [[ -d "$FFMPEG_INSTALL_DIR/include/libavformat" ]] || return 1
  [[ -f "$FFMPEG_INSTALL_DIR/lib/libavformat.a" ]] || return 1
  [[ -f "$FFMPEG_INSTALL_DIR/lib/libavcodec.a" ]] || return 1
  [[ -f "$FFMPEG_INSTALL_DIR/lib/libavfilter.a" ]] || return 1
  [[ -f "$FFMPEG_INSTALL_DIR/lib/libswresample.a" ]] || return 1
  [[ -f "$FFMPEG_INSTALL_DIR/lib/libswscale.a" ]] || return 1
  [[ -f "$FFMPEG_INSTALL_DIR/lib/libavutil.a" ]] || return 1
  if [[ "$ENABLE_PROGRAMS" == "1" ]]; then
    [[ -x "$FFMPEG_INSTALL_DIR/bin/ffmpeg" ]] || return 1
  fi
  return 0
}

SOURCE_REV="$(git -C "$FFMPEG_SRC_DIR" rev-parse HEAD 2>/dev/null || cat "$ROOT_DIR/ThirdParty/ffmpeg/VERSION.txt")"
CONFIGURE_FLAGS=(
  "--arch=$ARCH"
  "--target-os=darwin"
  "--extra-cflags=-isysroot $SDKROOT -mmacosx-version-min=13.0"
  "--extra-ldflags=-isysroot $SDKROOT -mmacosx-version-min=13.0"
  "--host-cflags=-isysroot $SDKROOT -mmacosx-version-min=13.0"
  "--host-ldflags=-isysroot $SDKROOT -mmacosx-version-min=13.0"
  "--disable-doc"
  "--enable-static"
  "--disable-shared"
  "--disable-gpl"
  "--disable-nonfree"
  "--enable-avcodec"
  "--enable-avformat"
  "--enable-avfilter"
  "--enable-swresample"
  "--enable-swscale"
  "--enable-avutil"
  "--disable-debug"
  "--disable-iconv"
  "--disable-x86asm"
)
BUILD_SIGNATURE="src=$SOURCE_REV|arch=$ARCH|sdk=$SDKROOT|cc=$CC|programs=$ENABLE_PROGRAMS|flags=$(printf '%s ' "${CONFIGURE_FLAGS[@]}")"

if [[ "$SKIP_FFMPEG_BUILD" == "1" ]]; then
  if required_artifacts_ready; then
    echo "Skipping FFmpeg build (SKIP_FFMPEG_BUILD=1), reusing: $FFMPEG_INSTALL_DIR"
    exit 0
  fi
  echo "SKIP_FFMPEG_BUILD=1 but required FFmpeg artifacts are missing." >&2
  echo "Run without SKIP_FFMPEG_BUILD to generate artifacts." >&2
  exit 1
fi

if [[ -f "$SIGNATURE_FILE" ]]; then
  CACHED_SIGNATURE="$(cat "$SIGNATURE_FILE")"
  if [[ "$CACHED_SIGNATURE" == "$BUILD_SIGNATURE" ]] && required_artifacts_ready; then
    echo "FFmpeg artifacts are up-to-date, skipping rebuild."
    echo "FFmpeg artifacts ready at: $FFMPEG_INSTALL_DIR"
    exit 0
  fi
elif required_artifacts_ready; then
  printf '%s\n' "$BUILD_SIGNATURE" > "$SIGNATURE_FILE"
  echo "Initialized FFmpeg build signature from existing artifacts."
  echo "FFmpeg artifacts ready at: $FFMPEG_INSTALL_DIR"
  exit 0
fi

mkdir -p "$FFMPEG_BUILD_DIR" "$FFMPEG_INSTALL_DIR" "$FFMPEG_INSTALL_DIR/$ARCH"

pushd "$FFMPEG_SRC_DIR" >/dev/null

if [[ -f "$SIGNATURE_FILE" ]]; then
  echo "FFmpeg build signature changed, running distclean..."
  make distclean >/dev/null 2>&1 || true
fi

./configure \
  --prefix="$FFMPEG_INSTALL_DIR/$ARCH" \
  --cc="$CC" \
  --host-cc="$CC" \
  "${CONFIGURE_FLAGS[@]}" \
  "${PROGRAM_FLAGS[@]}"

make -j"$JOBS"
make install

popd >/dev/null

rm -rf "$FFMPEG_INSTALL_DIR/include" "$FFMPEG_INSTALL_DIR/lib" "$FFMPEG_INSTALL_DIR/bin"
mkdir -p "$FFMPEG_INSTALL_DIR/include" "$FFMPEG_INSTALL_DIR/lib"

cp -R "$FFMPEG_INSTALL_DIR/$ARCH/include/." "$FFMPEG_INSTALL_DIR/include/"
cp "$FFMPEG_INSTALL_DIR/$ARCH/lib/"*.a "$FFMPEG_INSTALL_DIR/lib/"
if [[ "$ENABLE_PROGRAMS" == "1" && -x "$FFMPEG_INSTALL_DIR/$ARCH/bin/ffmpeg" ]]; then
  mkdir -p "$FFMPEG_INSTALL_DIR/bin"
  cp "$FFMPEG_INSTALL_DIR/$ARCH/bin/ffmpeg" "$FFMPEG_INSTALL_DIR/bin/ffmpeg"
  chmod +x "$FFMPEG_INSTALL_DIR/bin/ffmpeg"
fi

printf '%s\n' "$BUILD_SIGNATURE" > "$SIGNATURE_FILE"
echo "FFmpeg artifacts ready at: $FFMPEG_INSTALL_DIR"
