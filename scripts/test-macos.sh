#!/bin/sh
set -eu

PROJECT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIRECTORY/.tools/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIRECTORY/.tools/swift-module-cache"
SWIFT_BINARY=$(xcrun --find swiftc)
TESTING_PLUGIN="$(dirname -- "$SWIFT_BINARY")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"

set --
if [ -f "$TESTING_PLUGIN" ]; then
    # Some Command Line Tools builds omit automatic Swift Testing plugin discovery.
    set -- -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN"
fi

cd "$PROJECT_DIRECTORY/macos"
swift test --disable-sandbox --disable-xctest \
    --scratch-path "$PROJECT_DIRECTORY/.tools/swift-build" \
    --cache-path "$PROJECT_DIRECTORY/.tools/swiftpm-cache" \
    --config-path "$PROJECT_DIRECTORY/.tools/swiftpm-config" \
    --security-path "$PROJECT_DIRECTORY/.tools/swiftpm-security" "$@"
