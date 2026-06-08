#!/bin/sh

# Xcode Cloud runs this immediately after cloning the repository.
# The whisper.xcframework binary dependency is committed to the repo, so there
# is nothing to fetch here. Keep this script as a place to install any future
# dependencies (e.g. SPM resolves automatically; add Homebrew tools here if needed).

set -e

echo "ci_post_clone: repository checked out at $CI_WORKSPACE"
echo "ci_post_clone: nothing to install"
