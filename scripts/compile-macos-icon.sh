#!/bin/sh
set -eu

PROJECT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APPLICATION_DIRECTORY="$PROJECT_DIRECTORY/dist/Seamless.app"
RESOURCE_DIRECTORY="$APPLICATION_DIRECTORY/Contents/Resources"
PARTIAL_INFORMATION="$PROJECT_DIRECTORY/.tools/icon-information.plist"

if ! xcrun --find actool >/dev/null 2>&1; then
    if [ "${SEAMLESS_REQUIRE_NATIVE_ICON:-0}" = 1 ]; then
        printf '%s\n' 'Full Xcode with actool is required for native clear/tinted icon builds.' >&2
        exit 1
    fi
    printf '%s\n' 'Using legacy icon fallback; full Xcode enables native clear/tinted appearances.'
    exit 0
fi

xcrun actool "$PROJECT_DIRECTORY/macos/Support/Seamless.icon" \
    --compile "$RESOURCE_DIRECTORY" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --target-device mac \
    --app-icon Seamless \
    --output-partial-info-plist "$PARTIAL_INFORMATION"

python3 - "$APPLICATION_DIRECTORY/Contents/Info.plist" "$PARTIAL_INFORMATION" <<'PY'
import plistlib
import sys
from pathlib import Path

information_path = Path(sys.argv[1])
with information_path.open('rb') as stream:
    information = plistlib.load(stream)
with Path(sys.argv[2]).open('rb') as stream:
    information.update(plistlib.load(stream))
with information_path.open('wb') as stream:
    plistlib.dump(information, stream)
PY
