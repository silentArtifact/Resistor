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
