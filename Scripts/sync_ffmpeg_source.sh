#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_DIR="$ROOT_DIR/ThirdParty/ffmpeg"
FFMPEG_SOURCE_DIR="$FFMPEG_DIR/source"
VERSION_FILE="$FFMPEG_DIR/VERSION.txt"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing version file: $VERSION_FILE" >&2
  exit 1
fi

TAG="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ -z "$TAG" ]]; then
  echo "VERSION.txt is empty." >&2
  exit 1
fi

if [[ ! "$TAG" =~ ^n[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Only explicit release tags are allowed (example: n7.1.1). Found: $TAG" >&2
  exit 1
fi

if [[ ! -d "$FFMPEG_SOURCE_DIR/.git" ]]; then
  rm -rf "$FFMPEG_SOURCE_DIR"
  mkdir -p "$FFMPEG_DIR"
  git clone --depth 1 --branch "$TAG" https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_SOURCE_DIR"
else
  git -C "$FFMPEG_SOURCE_DIR" fetch --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG"
  git -C "$FFMPEG_SOURCE_DIR" checkout --force "$TAG"
fi

echo "FFmpeg source is synced at $FFMPEG_SOURCE_DIR ($TAG)."
