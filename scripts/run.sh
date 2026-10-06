#!/usr/bin/env bash
# Builds Ludeum (Debug) with scripts/build.sh and opens it, quitting any running copy first.
#   scripts/run.sh
set -euo pipefail

APP="$("$(dirname "$0")/build.sh")"
osascript -e 'quit app "Ludeum"' 2>/dev/null || true
while pgrep -x "Ludeum" >/dev/null; do sleep 0.2; done
open "$APP"
