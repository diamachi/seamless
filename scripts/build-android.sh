#!/bin/sh
set -eu

PROJECT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIRECTORY"
sh android/gradlew -p android --no-daemon :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
python3 - <<'PY'
from pathlib import Path
import re
import shutil

project_directory = Path.cwd()
configuration = (project_directory / "android/app/build.gradle.kts").read_text()
version_match = re.search(r'versionName\s*=\s*"([A-Za-z0-9.-]+)"', configuration)
if version_match is None:
    raise SystemExit("Cannot determine Android package version")
output_directory = project_directory / "dist"
output_directory.mkdir(exist_ok=True)
source = project_directory / "android/app/build/outputs/apk/debug/app-debug.apk"
destination = output_directory / f"Seamless-Android-{version_match.group(1)}.apk"
shutil.copyfile(source, destination)
print(f"Packaged {destination.name}")
PY
