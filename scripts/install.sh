#!/usr/bin/env bash
# Builds Pismo and installs it into ~/Applications (override with PISMO_INSTALL_DIR),
# replacing and restarting any running copy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Pismo"
INSTALL_DIR="${PISMO_INSTALL_DIR:-$HOME/Applications}"
DESTINATION="$INSTALL_DIR/$APP_NAME.app"

mkdir -p "$INSTALL_DIR"
if [[ ! -w "$INSTALL_DIR" ]]; then
  echo "Error: $INSTALL_DIR is not writable. Set PISMO_INSTALL_DIR to another directory." >&2
  exit 1
fi

"$ROOT/scripts/build.sh"

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

rm -rf "$DESTINATION"
ditto "$ROOT/build/$APP_NAME.app" "$DESTINATION"
open "$DESTINATION"
echo "Installed and started $DESTINATION"
