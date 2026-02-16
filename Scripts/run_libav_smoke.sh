#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

if [[ "${SKIP_FFMPEG_BUILD:-0}" == "1" ]]; then
  echo "[1/3] Skipping FFmpeg library build (SKIP_FFMPEG_BUILD=1)."
elif [[ -f "$ROOT_DIR/ThirdParty/ffmpeg-install/lib/libavformat.a" ]]; then
  echo "[1/3] Reusing existing FFmpeg static libraries."
else
  echo "[1/3] Building FFmpeg static libraries..."
  ./Scripts/build_ffmpeg_libs.sh
fi

echo "[2/3] Running libav integration tests..."
swift test --filter FFmpegEngineIntegrationTests

echo "[3/3] Smoke tests passed."
