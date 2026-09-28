#!/usr/bin/env bash
# Build the E-Trip Planer Android app (APK).
#
# Usage:
#   ./build_client.sh          # release APK → dist/trip_planner-<version>.apk
#   ./build_client.sh --debug  # debug APK   → build/app/outputs/flutter-apk/app-debug.apk
#
# Note: the release APK is signed with the debug key as long as no release
# signing config is set up in android/app/build.gradle.kts.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

DEBUG=false
for arg in "$@"; do
    case "$arg" in
        --debug) DEBUG=true ;;
        *) echo "Unbekannte Option: $arg" >&2; exit 1 ;;
    esac
done

# pubspec "version: 0.1.0+1" → name 0.1.0, build number 1
FULL_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')
APP_VERSION=${FULL_VERSION%%+*}
BUILD_NUMBER=${FULL_VERSION#*+}
echo "Version: $APP_VERSION ($BUILD_NUMBER)"

if $DEBUG; then
    echo "Building Android DEBUG…"
    flutter build apk --debug --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER"
    echo "Done: $DIR/build/app/outputs/flutter-apk/app-debug.apk"
else
    echo "Building Android RELEASE…"
    flutter build apk --release --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER"
    mkdir -p dist
    OUT="dist/trip_planner-$APP_VERSION.apk"
    cp build/app/outputs/flutter-apk/app-release.apk "$OUT"
    echo "Done: $DIR/$OUT"
fi
