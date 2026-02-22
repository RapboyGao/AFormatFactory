#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "$ROOT_DIR/Scripts/build_app.sh" ]]; then
  echo "Missing executable script: $ROOT_DIR/Scripts/build_app.sh" >&2
  exit 1
fi

exec "$ROOT_DIR/Scripts/build_app.sh" "$@"
