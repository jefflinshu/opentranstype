#!/bin/sh

# Xcode Cloud runs this right before xcodebuild.
# Set the build number (CFBundleVersion) to the Xcode Cloud build number so each
# TestFlight / App Store upload has a unique, increasing build number. The
# marketing version (CFBundleShortVersionString / MARKETING_VERSION) is left as
# configured in the project and bumped manually per release.

set -e

if [ -z "$CI_BUILD_NUMBER" ]; then
    echo "ci_pre_xcodebuild: CI_BUILD_NUMBER not set, skipping build-number override"
    exit 0
fi

echo "ci_pre_xcodebuild: setting build number to $CI_BUILD_NUMBER"

# agvtool needs to run from the directory containing the .xcodeproj.
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcrun agvtool new-version -all "$CI_BUILD_NUMBER"
