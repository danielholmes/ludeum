#!/usr/bin/env bash
# Generates the Xcode project and builds Ludeum (Debug), printing where the app is.
#   scripts/build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/.build/xcode"

cd "$ROOT"
xcodegen -q
xcodebuild -project Ludeum.xcodeproj -scheme Ludeum -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" build -quiet >&2
echo "$DERIVED/Build/Products/Debug/Ludeum.app"
