#!/bin/sh
set -eu

# Capture the result first so a missing Xcode fails even without a version pin.
xcode_version=$(xcodebuild -version) || exit 1
printf '%s\n' "$xcode_version"
if [ -n "${SCHNAPS_XCODE_VERSION:-}" ]; then
    actual_version=$(printf '%s\n' "$xcode_version" | head -n 1)
    if [ "$actual_version" != "Xcode $SCHNAPS_XCODE_VERSION" ]; then
        echo "Install/select Xcode $SCHNAPS_XCODE_VERSION (see README.md)" >&2
        exit 1
    fi
fi
