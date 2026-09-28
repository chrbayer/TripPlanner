#!/usr/bin/env bash
# Build the E-Trip Planer Linux desktop app.
#
# Usage:
#   ./build_desktop.sh           # release build → dist/trip_planner-<version>-linux-x64.tar.gz
#   ./build_desktop.sh --debug   # debug build   → build/linux/x64/debug/bundle/
#   ./build_desktop.sh --github  # release build, uploaded to the GitHub release v<version>

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

# pubspec "version: 0.1.0+1" → name 0.1.0, build number 1
FULL_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')
APP_VERSION=${FULL_VERSION%%+*}
BUILD_NUMBER=${FULL_VERSION#*+}
echo "Version: $APP_VERSION ($BUILD_NUMBER)"

TAG="v$APP_VERSION"
if $GITHUB; then
    # Everything is checked before the build: the release must be built from
    # exactly the tagged commit, or the published binary does not match the
    # published source.
    $DEBUG && fail "--github baut ein Release und passt nicht zu --debug."
    command -v gh >/dev/null || fail "gh (GitHub CLI) ist nicht installiert."
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
    echo "Building Linux DEBUG…"
    flutter build linux --debug --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER"
    echo "Done: $DIR/build/linux/x64/debug/bundle/trip_planner"
    exit 0
fi

echo "Building Linux RELEASE…"
flutter build linux --release --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER"
mkdir -p dist
OUT="dist/trip_planner-$APP_VERSION-linux-x64.tar.gz"
tar -czf "$OUT" -C build/linux/x64/release --transform "s|^bundle|trip_planner-$APP_VERSION|" bundle
echo "Done: $DIR/build/linux/x64/release/bundle/trip_planner"
echo "      $DIR/$OUT"

if ! $GITHUB; then
    exit 0
fi

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG gibt es schon, es kommt nur das Linux-Archiv dazu."
else
    gh release create "$TAG" --verify-tag --title "E-Trip Planer $APP_VERSION" \
        --notes "E-Trip Planer $APP_VERSION"
fi

# Deliberately no --clobber: a file that was already downloaded must not be
# swapped silently. To redo an upload, delete the asset by hand first
# (gh release delete-asset $TAG <file>).
gh release upload "$TAG" "$OUT"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo
echo "Release: https://github.com/$REPO/releases/tag/$TAG"
