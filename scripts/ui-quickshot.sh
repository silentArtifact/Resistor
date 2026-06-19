#!/usr/bin/env bash
#
# ui-quickshot.sh — Fast single-screen loop. Build, install, launch in
# -uiTestMode, and grab ONE screenshot of whatever's on screen. Much faster
# than the full UI-test walk; use it when iterating on the launch screen (Log).
#
# Usage:
#   scripts/ui-quickshot.sh [output.png]
#
# Output: build/ui-shots/quick.png (or the path you pass)

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="Resistor.xcodeproj"
SCHEME="Resistor"
SIM_NAME="${RESISTOR_SIM:-iPhone 17 Pro}"
DEST="platform=iOS Simulator,name=${SIM_NAME}"
DD="build/dd"
OUT="${1:-build/ui-shots/quick.png}"
BUNDLE_ID="com.resistor.app"

mkdir -p "$(dirname "$OUT")"

echo "▸ Booting ${SIM_NAME} (if needed)…"
xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
open -a Simulator || true

echo "▸ Building…"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -derivedDataPath "$DD" \
  2>&1 | tail -4

APP="$DD/Build/Products/Debug-iphonesimulator/Resistor.app"
echo "▸ Installing & launching…"
xcrun simctl install "$SIM_NAME" "$APP"
xcrun simctl terminate "$SIM_NAME" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$SIM_NAME" "$BUNDLE_ID" -uiTestMode >/dev/null

# Give SwiftUI a moment to render the first frame.
for i in 1 2 3 4 5 6; do sleep 0.5; done

echo "▸ Screenshot → $OUT"
xcrun simctl io "$SIM_NAME" screenshot "$OUT" 2>/dev/null
echo "▸ Done."
