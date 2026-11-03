#!/bin/sh
set -eu

PROJECT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIRECTORY"
BUILD_VARIANT=debug
if [ "${SEAMLESS_ANDROID_RELEASE:-auto}" = "1" ]; then
    BUILD_VARIANT=release
elif [ "${SEAMLESS_ANDROID_RELEASE:-auto}" = "auto" ] && [ -f "$PROJECT_DIRECTORY/.tools/android-signing.properties" ]; then
    BUILD_VARIANT=release
fi
if [ "$BUILD_VARIANT" = "release" ]; then
    sh android/gradlew -p android --no-daemon :app:assembleRelease :app:testReleaseUnitTest :app:lintRelease
else
    sh android/gradlew -p android --no-daemon :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
fi
export SEAMLESS_ANDROID_BUILD_VARIANT="$BUILD_VARIANT"
python3 - <<'PY'
from pathlib import Path
import re
import os
import subprocess
import shutil

project_directory = Path.cwd()
configuration = (project_directory / "android/app/build.gradle.kts").read_text()
version_match = re.search(r'versionName\s*=\s*"([A-Za-z0-9.-]+)"', configuration)
if version_match is None:
    raise SystemExit("Cannot determine Android package version")
output_directory = project_directory / "dist"
output_directory.mkdir(exist_ok=True)
variant = os.environ["SEAMLESS_ANDROID_BUILD_VARIANT"]
source = project_directory / f"android/app/build/outputs/apk/{variant}/app-{variant}.apk"
if not source.exists():
    raise SystemExit("Signed APK missing; configure the distribution signing key before packaging")
package_version = version_match.group(1).removesuffix("-dev")
destination = output_directory / f"Seamless_{package_version}.apk"
if variant == "release":
    sdk_directory = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk_directory:
        raise SystemExit("Set ANDROID_HOME to verify the distribution APK")
    verifier = Path(sdk_directory) / "build-tools/35.0.0/apksigner"
    verification = subprocess.run([str(verifier), "verify", "--print-certs", str(source)], capture_output=True, text=True)
    if verification.returncode != 0:
        raise SystemExit("Distribution APK signature verification failed")
    actual_digest = re.search(r'Signer #1 certificate SHA-256 digest: ([a-f0-9]{64})', verification.stdout)
    expected_digest = (project_directory / "android/signing-certificate.sha256").read_text().strip()
    if actual_digest is None or actual_digest.group(1) != expected_digest:
        raise SystemExit("Distribution APK signer does not match the approved signing certificate")
    print("Verified stable Android distribution signature")
shutil.copyfile(source, destination)
print(f"Packaged {destination.name}")
PY
