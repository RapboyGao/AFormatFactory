#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_SRC_DIR="$ROOT_DIR/ThirdParty/ffmpeg/source"
FFMPEG_BUILD_DIR="$ROOT_DIR/ThirdParty/ffmpeg-build"
FFMPEG_INSTALL_DIR="$ROOT_DIR/ThirdParty/ffmpeg-install"
ENABLE_PROGRAMS="${ENABLE_PROGRAMS:-0}"
SKIP_FFMPEG_BUILD="${SKIP_FFMPEG_BUILD:-0}"
SIGNATURE_FILE="$FFMPEG_INSTALL_DIR/.build_signature"

cpu_jobs() {
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu 2>/dev/null && return 0
  fi
  if command -v nproc >/dev/null 2>&1; then
    nproc && return 0
  fi
  echo 4
}

JOBS="${JOBS:-$(cpu_jobs)}"

if [[ ! -d "$FFMPEG_SRC_DIR/.git" ]]; then
  echo "FFmpeg source not found, syncing..."
  "$ROOT_DIR/Scripts/sync_ffmpeg_source.sh"
fi

UNAME_S="$(uname -s)"
UNAME_M="$(uname -m)"

case "$UNAME_M" in
  arm64|aarch64)
    ARCH="arm64"
    ;;
  x86_64|amd64)
    ARCH="x86_64"
    ;;
  *)
    echo "Unsupported architecture: $UNAME_M" >&2
    exit 1
    ;;
esac

TARGET_OS=""
CC="${CC:-clang}"
COMMON_FLAGS=(
  "--arch=$ARCH"
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
  "--disable-x86asm"
)
PLATFORM_FLAGS=()

case "$UNAME_S" in
  Darwin)
    TARGET_OS="darwin"
    SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
    CC="${CC:-$(xcrun --sdk macosx --find clang)}"
    PLATFORM_FLAGS=(
      "--target-os=$TARGET_OS"
      "--extra-cflags=-isysroot $SDKROOT -mmacosx-version-min=13.0"
      "--extra-ldflags=-isysroot $SDKROOT -mmacosx-version-min=13.0"
      "--host-cflags=-isysroot $SDKROOT -mmacosx-version-min=13.0"
      "--host-ldflags=-isysroot $SDKROOT -mmacosx-version-min=13.0"
      "--disable-iconv"
    )
    ;;
  Linux)
    TARGET_OS="linux"
    PLATFORM_FLAGS=(
      "--target-os=$TARGET_OS"
    )
    ;;
  MINGW*|MSYS*|CYGWIN*)
    TARGET_OS="mingw32"
    if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
      CC="${CC:-x86_64-w64-mingw32-gcc}"
    fi
    PLATFORM_FLAGS=(
      "--target-os=$TARGET_OS"
    )
    ;;
  *)
    echo "Unsupported OS: $UNAME_S" >&2
    exit 1
    ;;
esac

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
BUILD_SIGNATURE="src=$SOURCE_REV|os=$UNAME_S|arch=$ARCH|target_os=$TARGET_OS|cc=$CC|programs=$ENABLE_PROGRAMS|flags=$(printf '%s ' "${COMMON_FLAGS[@]}" "${PLATFORM_FLAGS[@]}")"

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
  "${COMMON_FLAGS[@]}" \
  "${PLATFORM_FLAGS[@]}" \
  "${PROGRAM_FLAGS[@]}"

make -j"$JOBS"
make install

popd >/dev/null

rm -rf "$FFMPEG_INSTALL_DIR/include" "$FFMPEG_INSTALL_DIR/lib" "$FFMPEG_INSTALL_DIR/bin"
mkdir -p "$FFMPEG_INSTALL_DIR/include" "$FFMPEG_INSTALL_DIR/lib"

cp -R "$FFMPEG_INSTALL_DIR/$ARCH/include/." "$FFMPEG_INSTALL_DIR/include/"

shopt -s nullglob
for lib in "$FFMPEG_INSTALL_DIR/$ARCH/lib/"*.a "$FFMPEG_INSTALL_DIR/$ARCH/lib/"*.lib; do
  cp "$lib" "$FFMPEG_INSTALL_DIR/lib/"
done
shopt -u nullglob

if [[ "$ENABLE_PROGRAMS" == "1" && -x "$FFMPEG_INSTALL_DIR/$ARCH/bin/ffmpeg" ]]; then
  mkdir -p "$FFMPEG_INSTALL_DIR/bin"
  cp "$FFMPEG_INSTALL_DIR/$ARCH/bin/ffmpeg" "$FFMPEG_INSTALL_DIR/bin/ffmpeg"
  chmod +x "$FFMPEG_INSTALL_DIR/bin/ffmpeg"
fi

printf '%s\n' "$BUILD_SIGNATURE" > "$SIGNATURE_FILE"
echo "FFmpeg artifacts ready at: $FFMPEG_INSTALL_DIR"
