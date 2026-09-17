#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
BUILD_ARGS=(-c release)
if [[ "${1:-}" == "--universal" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
elif [[ $# -gt 0 ]]; then
    print -u2 "Usage: $0 [--universal]"
    exit 1
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)
APP="$PWD/dist/TextSwitcher.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TextSwitcher" "$APP/Contents/MacOS/TextSwitcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Keep both native app localizations (per-app language settings) and the SwiftPM
# resource bundle (Bundle.module fallback) in the distributable app.
for locale in Sources/TextSwitcherCore/Resources/*.lproj; do
    ditto "$locale" "$APP/Contents/Resources/${locale:t}"
done
ditto "$BIN_DIR/TextSwitcher_TextSwitcherCore.bundle" "$APP/Contents/Resources/TextSwitcher_TextSwitcherCore.bundle"
swift scripts/icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.textswitcher.app "$APP"
print "Built: $APP"
