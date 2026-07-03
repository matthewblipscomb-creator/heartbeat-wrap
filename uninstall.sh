#!/bin/bash
# uninstall.sh
#
# heartbeat_wrap.sh has no real "install" step (see README.md) - it's a
# single file you run directly or copy onto your PATH. The only thing it
# ever writes anywhere is its own local data directory, ~/.heartbeat_wrap/
# (job registry snapshots for the dashboard, and the optional --history
# SQLite DB). This script just removes that directory, plus any copy of
# heartbeat_wrap.sh it can find on your PATH, so there's a clean, explicit
# way to fully remove everything if you ever want to.
#
# Usage:
#   ./uninstall.sh            # interactive, asks before deleting anything
#   ./uninstall.sh --yes      # skip confirmation (for scripting)

set -uo pipefail

DATA_DIR="${HOME}/.heartbeat_wrap"
ASSUME_YES=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=1

echo "This will remove:"
echo "  - ${DATA_DIR} (job registry snapshots + --history SQLite DB, if present)"

FOUND_ON_PATH=""
if command -v heartbeat_wrap.sh >/dev/null 2>&1; then
  FOUND_ON_PATH="$(command -v heartbeat_wrap.sh)"
  echo "  - ${FOUND_ON_PATH} (found on your PATH)"
fi

if [[ ! -d "$DATA_DIR" && -z "$FOUND_ON_PATH" ]]; then
  echo "Nothing to remove - no ${DATA_DIR} and no heartbeat_wrap.sh found on PATH."
  exit 0
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -r -p "Proceed? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled - nothing removed."; exit 0 ;;
  esac
fi

if [[ -d "$DATA_DIR" ]]; then
  rm -rf "$DATA_DIR"
  echo "Removed ${DATA_DIR}"
fi

if [[ -n "$FOUND_ON_PATH" ]]; then
  rm -f "$FOUND_ON_PATH"
  echo "Removed ${FOUND_ON_PATH}"
fi

echo "Done. If you cloned/copied this repo elsewhere (e.g. this very folder), delete that folder manually too - this script only removes the PATH copy + local data dir."
