#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-tauri}"
shift || true

exec node "$ROOT_DIR/Scripts/build_target.mjs" "$TARGET" "$@"
