#!/bin/sh
#
# Xcode Cloud post-clone hook.
#
# Stamps the build number from Xcode Cloud's own monotonic build counter so
# every TestFlight upload gets a unique CFBundleVersion. Without this the
# checked-in CURRENT_PROJECT_VERSION (1) would be re-uploaded on every push to
# main and App Store Connect would reject it as a duplicate — which is a build
# failure email per push, the exact thing the .complication rename just fixed.
#
# Every target's Info.plist resolves CFBundleVersion from $(CURRENT_PROJECT_VERSION),
# so rewriting the one build setting covers app, widget, watch app and complication.
# The project has no VERSIONING_SYSTEM and uses GENERATE_INFOPLIST_FILE, so agvtool
# is not an option here.
#
# `set -eu` is load-bearing: an unset CI_BUILD_NUMBER would otherwise sed the
# version to empty and ship a bundle with no CFBundleVersion.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/g" \
  Resistor.xcodeproj/project.pbxproj

echo "Set CURRENT_PROJECT_VERSION to $CI_BUILD_NUMBER"

# TestFlight "What to Test" notes. Xcode Cloud reads TestFlight/WhatToTest.<locale>.txt
# from the repository root during the TestFlight deployment and shows it to testers as
# release notes; with no file the field is blank and a build says nothing about itself.
#
# Two sources, in priority order:
#
#   1. Hand-written notes, if TestFlight/WhatToTest.en-US.txt was touched by the commit
#      being built. Prose aimed at a tester ("log a temptation on the watch, check it
#      reaches the phone") beats anything derivable from git.
#   2. Otherwise the commit SUBJECT line, overwriting whatever is on disk.
#
# The "touched by this commit" test is what makes checked-in notes safe. A committed file
# left alone goes stale on the next push and then describes the PREVIOUS build — worse
# than blank, because stale notes read as true. Requiring the file to be part of the
# commit means notes are either deliberately current or regenerated from HEAD; they can
# never silently describe something that didn't ship.
#
# Subject only, never the body: these commit messages explain implementation rationale to
# whoever reads git history later, which is the wrong register entirely for a tester.
NOTES=TestFlight/WhatToTest.en-US.txt
mkdir -p TestFlight

if git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | grep -qx "$NOTES"; then
  echo "Using hand-written test notes from this commit"
else
  git log -1 --pretty=format:'%s' > "$NOTES"
  echo >> "$NOTES"
  echo "Generated test notes from the commit subject"
fi

echo "--- WhatToTest.en-US.txt ---"
cat "$NOTES"
