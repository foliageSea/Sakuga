#!/usr/bin/env bash
# Run Sakuga on Linux with the local media libraries and the WSLg-friendly
# renderer settings. Use `tool/linux_deps.sh` first if system libs are missing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="$("$ROOT_DIR/tool/linux_deps.sh")"
LIB_DIRS="$(printf '%s' "$DEPS" | paste -sd: -)"

export LD_LIBRARY_PATH="${LIB_DIRS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GDK_BACKEND="${GDK_BACKEND:-x11}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"

cd "$ROOT_DIR"
exec fvm flutter run -d linux "$@"
