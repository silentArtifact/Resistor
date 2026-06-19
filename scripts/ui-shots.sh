#!/usr/bin/env bash
#
# ui-shots.sh — Build the app, run the XCUITest snapshot walk, and export one
# PNG per screen into build/ui-shots/ with friendly names (01-Log.png, …).
#
# This is the primary screenshot harness for the UI iteration loop. It launches
# the app in -uiTestMode (clean in-memory seeded data, no onboarding, no
# CloudKit) so every run renders identical content.
#
# Usage:
#   scripts/ui-shots.sh            # light mode → 01-Log.png … 04-Habits.png
#   scripts/ui-shots.sh --dark     # dark mode  → 01-Log-dark.png … 04-Habits-dark.png
#
# Light and dark captures coexist on disk; each mode only cleans its own files,
# so you can run both and compare appearances side by side.
#
# Output: build/ui-shots/*.png  (read these with the Read tool)

set -euo pipefail
cd "$(dirname "$0")/.."

DARK=0
if [[ "${1:-}" == "--dark" ]]; then DARK=1; fi

PROJECT="Resistor.xcodeproj"
SCHEME="ResistorUITests"
SIM_NAME="${RESISTOR_SIM:-iPhone 17 Pro}"
DEST="platform=iOS Simulator,name=${SIM_NAME}"
RESULT_BUNDLE="build/ui-shots.xcresult"
OUT_DIR="build/ui-shots"
EXPORT_DIR="build/ui-shots-export"

if [[ "$DARK" == "1" ]]; then
  TEST_METHOD="testCaptureAllScreensDark"
  MODE_LABEL="dark"
else
  TEST_METHOD="testCaptureAllScreens"
  MODE_LABEL="light"
fi

echo "▸ Cleaning previous ${MODE_LABEL} run…"
# Each mode removes only ITS OWN numbered captures, so light and dark coexist.
# Anything copied aside for comparison — especially build/ui-shots/saved/ — is
# always preserved across runs.
rm -rf "$RESULT_BUNDLE" "$EXPORT_DIR"
mkdir -p "$OUT_DIR" "$OUT_DIR/saved"
if [[ "$DARK" == "1" ]]; then
  find "$OUT_DIR" -maxdepth 1 -name '*-dark.png' -delete
else
  find "$OUT_DIR" -maxdepth 1 -name '[0-9][0-9]-*.png' ! -name '*-dark.png' -delete
fi

echo "▸ Building & running ${MODE_LABEL} snapshot walk on ${SIM_NAME}…"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -only-testing:ResistorUITests/SnapshotTests/"$TEST_METHOD" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -derivedDataPath build/dd \
  2>&1 | tail -8

echo "▸ Exporting screenshot attachments…"
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$EXPORT_DIR" >/dev/null

echo "▸ Renaming to friendly names…"
ruby - "$EXPORT_DIR" "$OUT_DIR" <<'RUBY'
require "json"
require "fileutils"
export_dir, out_dir = ARGV
manifest = JSON.parse(File.read(File.join(export_dir, "manifest.json")))
count = 0
manifest.each do |test|
  (test["attachments"] || []).each do |att|
    name = att["suggestedHumanReadableName"] || att["exportedFileName"]
    src  = File.join(export_dir, att["exportedFileName"])
    next unless File.exist?(src)
    # suggestedHumanReadableName looks like "01-Log_0_<UUID>.png" — strip the
    # attachment index + UUID suffix back to the name set in the test (the test
    # already bakes any "-dark" suffix into that name).
    base = name.sub(/_\d+_[0-9A-Fa-f-]{36}\.png$/, "").sub(/\.png$/i, "")
    FileUtils.cp(src, File.join(out_dir, "#{base}.png"))
    count += 1
  end
end
puts "  wrote #{count} screenshot(s)"
RUBY

echo "▸ Done (${MODE_LABEL}). Screens in ${OUT_DIR}/:"
ls -1 "$OUT_DIR"/*.png 2>/dev/null | sed 's/^/   /' || echo "   (none — check the xcodebuild output above)"
