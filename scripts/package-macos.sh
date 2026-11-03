#!/bin/sh
set -eu

PROJECT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APPLICATION_DIRECTORY="$PROJECT_DIRECTORY/dist/Seamless.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APPLICATION_DIRECTORY/Contents/Info.plist")
STAGING_DIRECTORY=$(mktemp -d "$PROJECT_DIRECTORY/.tools/dmg-staging.XXXXXX")
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT HUP INT TERM

# A test image must not distribute the developer's personal signing certificate.
ditto --noextattr --norsrc "$APPLICATION_DIRECTORY" "$STAGING_DIRECTORY/Seamless.app"
strip -S "$STAGING_DIRECTORY/Seamless.app/Contents/MacOS/Seamless"
codesign --force --sign - "$STAGING_DIRECTORY/Seamless.app"
codesign --verify --deep --strict "$STAGING_DIRECTORY/Seamless.app"
ln -s /Applications "$STAGING_DIRECTORY/Applications"
IMAGE_PATH="$PROJECT_DIRECTORY/dist/Seamless_$VERSION.dmg"
hdiutil create -volname Seamless -srcfolder "$STAGING_DIRECTORY" -format UDZO -ov "$IMAGE_PATH"
hdiutil verify "$IMAGE_PATH"
printf 'Packaged %s\n' "$IMAGE_PATH"
