#!/usr/bin/env bash
# Builds Ludeum (Debug) and opens it, quitting any running copy first.
#   scripts/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/.build/xcode"
APP="$DERIVED/Build/Products/Debug/Ludeum.app"

cd "$ROOT"
xcodegen -q
xcodebuild -project Ludeum.xcodeproj -scheme Ludeum -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" build -quiet
osascript -e 'quit app "Ludeum"' 2>/dev/null || true
while pgrep -x "Ludeum" >/dev/null; do sleep 0.2; done
open "$APP"
