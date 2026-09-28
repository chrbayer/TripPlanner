#!/usr/bin/env bash
# Build the E-Trip Planer Linux desktop app.
#
# Usage:
#   ./build_desktop.sh          # release build → dist/trip_planner-<version>-linux-x64.tar.gz
#   ./build_desktop.sh --debug  # debug build   → build/linux/x64/debug/bundle/

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
    echo "Building Linux DEBUG…"
    flutter build linux --debug --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER"
    echo "Done: $DIR/build/linux/x64/debug/bundle/trip_planner"
else
    echo "Building Linux RELEASE…"
    flutter build linux --release --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER"
    mkdir -p dist
    OUT="dist/trip_planner-$APP_VERSION-linux-x64.tar.gz"
    tar -czf "$OUT" -C build/linux/x64/release --transform "s|^bundle|trip_planner-$APP_VERSION|" bundle
    echo "Done: $DIR/build/linux/x64/release/bundle/trip_planner"
    echo "      $DIR/$OUT"
fi
