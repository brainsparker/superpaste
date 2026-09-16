#!/bin/bash
# Shared values are consumed by the scripts sourcing this file.
# shellcheck disable=SC2034

SOURCE_INFO_PLIST="$REPO/SuperPaste/Resources/Info.plist"
DEV_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_INFO_PLIST").dev"
DEV_APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$SOURCE_INFO_PLIST") Dev"
DEV_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SOURCE_INFO_PLIST")Dev"
DEV_APP="$REPO/$DEV_APP_NAME.app"
