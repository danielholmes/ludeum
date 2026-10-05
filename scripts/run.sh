#!/usr/bin/env bash
# Builds Games Journal (Debug) and opens it, quitting any running copy first.
#   scripts/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/.build/xcode"
APP="$DERIVED/Build/Products/Debug/Games Journal.app"

cd "$ROOT"
xcodegen -q
xcodebuild -project GamesJournal.xcodeproj -scheme GamesJournal -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" build -quiet
osascript -e 'quit app "Games Journal"' 2>/dev/null || true
while pgrep -x "Games Journal" >/dev/null; do sleep 0.2; done
open "$APP"
