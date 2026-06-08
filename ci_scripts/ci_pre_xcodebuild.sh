#!/bin/sh

# Xcode Cloud runs this right before xcodebuild.
#
# This project uses GENERATE_INFOPLIST_FILE = YES (no standalone Info.plist), so
# the build number comes from the CURRENT_PROJECT_VERSION build setting, not from
# a plist. agvtool does NOT work here. Instead we rewrite CURRENT_PROJECT_VERSION
# in the project file to the Xcode Cloud build number so each TestFlight / App
# Store upload has a unique, increasing build number.
#
# The marketing version (MARKETING_VERSION) is left as configured and bumped
# manually per release.

set -e

if [ -z "$CI_BUILD_NUMBER" ]; then
    echo "ci_pre_xcodebuild: CI_BUILD_NUMBER not set, skipping build-number override"
    exit 0
fi

PROJECT_FILE="$CI_PRIMARY_REPOSITORY_PATH/opentranstype.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "ci_pre_xcodebuild: project file not found at $PROJECT_FILE"
    exit 1
fi

echo "ci_pre_xcodebuild: setting CURRENT_PROJECT_VERSION to $CI_BUILD_NUMBER"

# Replace every CURRENT_PROJECT_VERSION value (Debug + Release) with the build number.
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" "$PROJECT_FILE"

echo "ci_pre_xcodebuild: result ->"
grep "CURRENT_PROJECT_VERSION" "$PROJECT_FILE" | sort -u
