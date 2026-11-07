#!/usr/bin/env bash
# Builds "build/Zune Manager.app" (release build, ad-hoc signed). Needs only the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ZuneManager
BIN=$(swift build -c release --product ZuneManager --show-bin-path)/ZuneManager

APP="build/Zune Manager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ZuneManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"
echo "$PWD/$APP"
