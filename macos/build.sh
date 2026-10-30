#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS with Xcode Command Line Tools is required to build WubiCoach.app." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/macos"
OUTPUT="$ROOT/dist/macOS"
ARCHES=("$(uname -m)")
SUFFIX="${ARCHES[0]}"
if [[ "${1:-}" == "--universal" ]]; then
  ARCHES=(arm64 x86_64)
  SUFFIX="universal"
elif [[ $# -gt 0 ]]; then
  echo "Usage: bash macos/build.sh [--universal]" >&2
  exit 1
fi

mkdir -p "$OUTPUT"
BINARIES=()
for ARCH in "${ARCHES[@]}"; do
  OPTIONS=(--package-path "$PACKAGE" --scratch-path "$PACKAGE/.build/$ARCH" -c release --triple "$ARCH-apple-macosx13.0")
  xcrun swift build "${OPTIONS[@]}"
  BIN_DIR="$(xcrun swift build "${OPTIONS[@]}" --show-bin-path)"
  BINARIES+=("$BIN_DIR/WubiCoach")
done

APP="$OUTPUT/WubiCoach.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/data"
if [[ ${#BINARIES[@]} -gt 1 ]]; then
  xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/WubiCoach"
else
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/WubiCoach"
fi
chmod +x "$APP/Contents/MacOS/WubiCoach"
cp "$PACKAGE/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT"/data/* "$APP/Contents/Resources/data/"
cp "$ROOT/README.md" "$ROOT/THIRD-PARTY.md" "$ROOT/LICENSE" "$APP/Contents/Resources/"
# Local ad-hoc signing. This is not Developer ID signing or Apple notarization.
codesign --force --sign - --identifier org.wubicoach.desktop "$APP"
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "$OUTPUT/WubiCoach-macOS-$SUFFIX.zip"
echo "Built: $APP"
echo "Archive: $OUTPUT/WubiCoach-macOS-$SUFFIX.zip"
