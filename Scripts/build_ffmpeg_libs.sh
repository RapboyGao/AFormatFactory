#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_SRC_DIR="$ROOT_DIR/ThirdParty/ffmpeg/source"
FFMPEG_BUILD_DIR="$ROOT_DIR/ThirdParty/ffmpeg-build"
FFMPEG_INSTALL_DIR="$ROOT_DIR/ThirdParty/ffmpeg-install"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
ENABLE_PROGRAMS="${ENABLE_PROGRAMS:-1}"

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

mkdir -p "$FFMPEG_BUILD_DIR" "$FFMPEG_INSTALL_DIR"
rm -rf "$FFMPEG_BUILD_DIR/$ARCH" "$FFMPEG_INSTALL_DIR/$ARCH"
mkdir -p "$FFMPEG_BUILD_DIR/$ARCH" "$FFMPEG_INSTALL_DIR/$ARCH"

pushd "$FFMPEG_SRC_DIR" >/dev/null

PROGRAM_FLAGS=(--disable-programs)
if [[ "$ENABLE_PROGRAMS" == "1" ]]; then
  PROGRAM_FLAGS=(--enable-ffmpeg --disable-ffplay --disable-ffprobe)
fi

./configure \
  --prefix="$FFMPEG_INSTALL_DIR/$ARCH" \
  --cc="$CC" \
  --host-cc="$CC" \
  --arch="$ARCH" \
  --target-os=darwin \
  --extra-cflags="-isysroot $SDKROOT -mmacosx-version-min=13.0" \
  --extra-ldflags="-isysroot $SDKROOT -mmacosx-version-min=13.0" \
  --host-cflags="-isysroot $SDKROOT -mmacosx-version-min=13.0" \
  --host-ldflags="-isysroot $SDKROOT -mmacosx-version-min=13.0" \
  --disable-doc \
  --enable-static \
  --disable-shared \
  --disable-gpl \
  --disable-nonfree \
  --enable-avcodec \
  --enable-avformat \
  --enable-avfilter \
  --enable-swresample \
  --enable-swscale \
  --enable-avutil \
  --disable-debug \
  --disable-iconv \
  --disable-x86asm \
  "${PROGRAM_FLAGS[@]}"

make -j"$JOBS"
make install

make distclean
popd >/dev/null

rm -rf "$FFMPEG_INSTALL_DIR/include" "$FFMPEG_INSTALL_DIR/lib" "$FFMPEG_INSTALL_DIR/bin"
mkdir -p "$FFMPEG_INSTALL_DIR/include" "$FFMPEG_INSTALL_DIR/lib" "$FFMPEG_INSTALL_DIR/bin"

cp -R "$FFMPEG_INSTALL_DIR/$ARCH/include/." "$FFMPEG_INSTALL_DIR/include/"
cp "$FFMPEG_INSTALL_DIR/$ARCH/lib/"*.a "$FFMPEG_INSTALL_DIR/lib/"
if [[ "$ENABLE_PROGRAMS" == "1" && -x "$FFMPEG_INSTALL_DIR/$ARCH/bin/ffmpeg" ]]; then
  cp "$FFMPEG_INSTALL_DIR/$ARCH/bin/ffmpeg" "$FFMPEG_INSTALL_DIR/bin/ffmpeg"
  chmod +x "$FFMPEG_INSTALL_DIR/bin/ffmpeg"
fi

echo "FFmpeg artifacts ready at: $FFMPEG_INSTALL_DIR"
