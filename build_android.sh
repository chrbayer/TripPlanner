#!/usr/bin/env bash
# Build the E-Trip Planer Android app (APK).
#
# Usage:
#   ./build_android.sh           # release APK → dist/trip_planner-<version>.apk
#   ./build_android.sh --debug   # debug APK   → build/app/outputs/flutter-apk/app-debug.apk
#   ./build_android.sh --github  # additionally one APK per ABI, and all of them
#                                # uploaded to the GitHub release v<version>
#
# Release signing via environment variables:
#   TP_KEYSTORE_PATH     path to .keystore / .jks file
#   TP_KEYSTORE_ALIAS    key alias inside the keystore (default: tripplanner)
#   TP_KEYSTORE_PASS     keystore + key password
#
# If TP_KEYSTORE_PATH is unset the release APK is signed with the debug key and
# the script says so. Such an APK cannot later be updated by a properly signed
# one, so do not hand it out. --github refuses to run that way.
#
# Set the password in your own terminal, not through a tool that records input:
#   export TP_KEYSTORE_PASS="$(systemd-ask-password 'Kennwort:')"
#   export TP_KEYSTORE_PATH=~/keys/tripplanner-release.jks
#   ./build_android.sh --github

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

fail() { echo "FEHLER: $*" >&2; exit 1; }

DEBUG=false
GITHUB=false
for arg in "$@"; do
    case "$arg" in
        --debug)  DEBUG=true ;;
        --github) GITHUB=true ;;
        *) fail "Unbekannte Option: $arg" ;;
    esac
done

# pubspec "version: 0.1.1+2" → name 0.1.1, build number 2. The Android
# versionCode becomes build number * 10 plus an ABI digit (build.gradle.kts).
FULL_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')
[[ "$FULL_VERSION" == *+* ]] || fail "pubspec.yaml braucht eine Version mit Build-Nummer, z. B. 0.1.1+2."
APP_VERSION=${FULL_VERSION%%+*}
BUILD_NUMBER=${FULL_VERSION#*+}
VERSION_ARGS=(--build-name="$APP_VERSION" --build-number="$BUILD_NUMBER")
echo "Version: $APP_VERSION ($BUILD_NUMBER)"

TAG="v$APP_VERSION"
if $GITHUB; then
    # Everything is checked before the first build: finding out after minutes
    # of Gradle that the tag is missing helps nobody.
    $DEBUG && fail "--github baut Release-APKs und passt nicht zu --debug."
    [[ -n "${TP_KEYSTORE_PATH:-}" && -n "${TP_KEYSTORE_PASS:-}" ]] \
        || fail "TP_KEYSTORE_PATH und TP_KEYSTORE_PASS müssen gesetzt sein. Ein Release mit dem Debug-Schlüssel wird nicht veröffentlicht."
    command -v gh >/dev/null || fail "gh (GitHub CLI) ist nicht installiert."

    # The release must be built from exactly the tagged commit, or the
    # published APKs do not match the published source.
    [[ -z "$(git status --porcelain --untracked-files=no)" ]] \
        || fail "Es gibt nicht committete Änderungen. Das Release muss genau aus $TAG gebaut werden."
    TAG_COMMIT=$(git rev-parse -q --verify "$TAG^{commit}" || true)
    [[ -n "$TAG_COMMIT" ]] || fail "Den Tag $TAG gibt es nicht."
    [[ "$(git rev-parse HEAD)" == "$TAG_COMMIT" ]] \
        || fail "HEAD ist nicht $TAG. Erst 'git checkout $TAG' oder den Tag auf den richtigen Commit setzen."
    git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null \
        || fail "$TAG ist noch nicht auf GitHub. Erst 'git push origin $TAG'."
fi

if $DEBUG; then
    echo "Building Android DEBUG…"
    flutter build apk --debug "${VERSION_ARGS[@]}"
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

APK_DIR="$DIR/build/app/outputs/flutter-apk"
mkdir -p dist

echo "Building Android RELEASE (universal)…"
flutter build apk --release "${VERSION_ARGS[@]}"
ASSETS=("dist/trip_planner-$APP_VERSION.apk")
cp -f "$APK_DIR/app-release.apk" "${ASSETS[0]}"

if $GITHUB; then
    # One build produces all three: smaller downloads for users who know
    # their device's architecture.
    echo "Building one APK per ABI…"
    flutter build apk --release --split-per-abi "${VERSION_ARGS[@]}"
    for abi in armeabi-v7a arm64-v8a x86_64; do
        asset="dist/trip_planner-$APP_VERSION-$abi.apk"
        cp -f "$APK_DIR/app-$abi-release.apk" "$asset"
        ASSETS+=("$asset")
    done
fi

# Say which key was used. With a keystore given, a debug signature means the
# signing config did not apply - fail rather than ship it.
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
APKSIGNER=$(find "$SDK/build-tools" -mindepth 2 -maxdepth 2 -name apksigner -type f 2>/dev/null | sort -V | tail -1 || true)
if [[ -n "$APKSIGNER" ]]; then
    for asset in "${ASSETS[@]}"; do
        signer=$("$APKSIGNER" verify --print-certs "$asset" 2>/dev/null | sed -n 's/.*certificate DN: //p' | head -1)
        echo "$(basename "$asset"): $signer"
        if $SIGNED && [[ "$signer" == *"Android Debug"* ]]; then
            rm -f "${ASSETS[@]}"
            fail "$(basename "$asset") ist trotz Keystore mit dem Debug-Schlüssel signiert."
        fi
    done
else
    $GITHUB && fail "apksigner nicht gefunden, die Signatur kann nicht geprüft werden."
    echo "WARNUNG: apksigner nicht gefunden, die Signatur wurde nicht geprüft." >&2
fi

if ! $GITHUB; then
    echo "Done: $DIR/${ASSETS[0]}"
    exit 0
fi

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG gibt es schon, es kommen nur die APKs dazu."
else
    gh release create "$TAG" --verify-tag --title "E-Trip Planer $APP_VERSION" \
        --notes "E-Trip Planer $APP_VERSION"
fi

# Deliberately no --clobber: a file that was already downloaded must not be
# swapped silently. To redo an upload, delete the asset by hand first
# (gh release delete-asset $TAG <file>).
gh release upload "$TAG" "${ASSETS[@]}"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo
echo "Release: https://github.com/$REPO/releases/tag/$TAG"
