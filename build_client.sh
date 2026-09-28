#!/usr/bin/env bash
# Build the E-Trip Planer Android app (APK).
#
# Usage:
#   ./build_client.sh          # release APK → dist/trip_planner-<version>.apk
#   ./build_client.sh --debug  # debug APK   → build/app/outputs/flutter-apk/app-debug.apk
#
# Release signing via environment variables:
#   TP_KEYSTORE_PATH     path to .keystore / .jks file
#   TP_KEYSTORE_ALIAS    key alias inside the keystore (default: tripplanner)
#   TP_KEYSTORE_PASS     keystore + key password
#
# If TP_KEYSTORE_PATH is unset the release APK is signed with the debug key and
# the script says so. Such an APK cannot later be updated by a properly signed
# one, so do not hand it out.
#
# Set the password in your own terminal, not through a tool that records input:
#   export TP_KEYSTORE_PASS="$(systemd-ask-password 'Kennwort:')"
#   export TP_KEYSTORE_PATH=~/keys/tripplanner-release.jks
#   ./build_client.sh

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

fail() { echo "FEHLER: $*" >&2; exit 1; }

DEBUG=false
for arg in "$@"; do
    case "$arg" in
        --debug) DEBUG=true ;;
        *) fail "Unbekannte Option: $arg" ;;
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
    exit 0
fi

# Write key.properties for release signing if a keystore is given; it is
# removed again on exit so the password never stays on disk.
KEY_PROPS="$DIR/android/key.properties"
SIGNED=false
if [[ -n "${TP_KEYSTORE_PATH:-}" ]]; then
    [[ -f "$TP_KEYSTORE_PATH" ]] || fail "Keystore nicht gefunden: $TP_KEYSTORE_PATH"
    [[ -n "${TP_KEYSTORE_PASS:-}" ]] || fail "TP_KEYSTORE_PASS ist nicht gesetzt."
    trap 'rm -f "$KEY_PROPS"' EXIT
    (umask 077; cat > "$KEY_PROPS" << PROPS
storePassword=${TP_KEYSTORE_PASS}
keyPassword=${TP_KEYSTORE_PASS}
keyAlias=${TP_KEYSTORE_ALIAS:-tripplanner}
storeFile=${TP_KEYSTORE_PATH}
PROPS
    )
    SIGNED=true
else
    echo "WARNUNG: TP_KEYSTORE_PATH ist nicht gesetzt, die APK wird mit dem Debug-Schlüssel signiert." >&2
fi

echo "Building Android RELEASE…"
flutter build apk --release --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER"
mkdir -p dist
OUT="dist/trip_planner-$APP_VERSION.apk"
cp -f build/app/outputs/flutter-apk/app-release.apk "$OUT"

# Say which key was used. With a keystore given, a debug signature means the
# signing config did not apply - fail rather than ship it.
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
APKSIGNER=$(find "$SDK/build-tools" -mindepth 2 -maxdepth 2 -name apksigner -type f 2>/dev/null | sort -V | tail -1 || true)
if [[ -n "$APKSIGNER" ]]; then
    signer=$("$APKSIGNER" verify --print-certs "$OUT" | sed -n 's/.*certificate DN: //p' | head -1)
    echo "Signiert von: $signer"
    if $SIGNED && [[ "$signer" == *"Android Debug"* ]]; then
        rm -f "$OUT"
        fail "Trotz Keystore mit dem Debug-Schlüssel signiert."
    fi
else
    echo "WARNUNG: apksigner nicht gefunden, die Signatur wurde nicht geprüft." >&2
fi

echo "Done: $DIR/$OUT"
