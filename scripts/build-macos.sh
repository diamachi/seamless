#!/bin/sh
set -eu

PROJECT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIRECTORY="$PROJECT_DIRECTORY/.tools/swift-build"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIRECTORY/.tools/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIRECTORY/.tools/swift-module-cache"

cd "$PROJECT_DIRECTORY/macos"
swift build --configuration release \
    --disable-sandbox \
    --scratch-path "$BUILD_DIRECTORY" \
    --cache-path "$PROJECT_DIRECTORY/.tools/swiftpm-cache" \
    --config-path "$PROJECT_DIRECTORY/.tools/swiftpm-config" \
    --security-path "$PROJECT_DIRECTORY/.tools/swiftpm-security"

APPLICATION_DIRECTORY="$PROJECT_DIRECTORY/dist/Seamless.app"
mkdir -p "$APPLICATION_DIRECTORY/Contents/MacOS"
cp "$BUILD_DIRECTORY/release/Seamless" "$APPLICATION_DIRECTORY/Contents/MacOS/Seamless"
cp "$PROJECT_DIRECTORY/macos/Support/Info.plist" "$APPLICATION_DIRECTORY/Contents/Info.plist"
mkdir -p "$APPLICATION_DIRECTORY/Contents/Resources"
cp "$PROJECT_DIRECTORY/macos/Support/Seamless.icns" "$APPLICATION_DIRECTORY/Contents/Resources/Seamless.icns"
cp "$PROJECT_DIRECTORY/macos/Support/SeamlessLight.icns" "$APPLICATION_DIRECTORY/Contents/Resources/SeamlessLight.icns"
# A rebuilt legacy-only app must not retain a previous native icon asset catalog.
rm -f "$APPLICATION_DIRECTORY/Contents/Resources/Assets.car"
sh "$PROJECT_DIRECTORY/scripts/compile-macos-icon.sh"
SIGNING_IDENTITY="${SEAMLESS_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ] && [ -f "$PROJECT_DIRECTORY/.tools/signing-identity" ]; then
    SIGNING_IDENTITY=$(cat "$PROJECT_DIRECTORY/.tools/signing-identity")
fi
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="-"
fi
codesign --force --sign "$SIGNING_IDENTITY" "$APPLICATION_DIRECTORY"
printf 'Built %s\n' "$APPLICATION_DIRECTORY"
