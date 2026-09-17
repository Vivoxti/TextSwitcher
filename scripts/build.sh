#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
APP="$PWD/dist/TextSwitcher.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TextSwitcher "$APP/Contents/MacOS/TextSwitcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Keep both native app localizations (per-app language settings) and the SwiftPM
# resource bundle (Bundle.module fallback) in the distributable app.
for locale in Sources/TextSwitcherCore/Resources/*.lproj; do
    ditto "$locale" "$APP/Contents/Resources/${locale:t}"
done
ditto .build/release/TextSwitcher_TextSwitcherCore.bundle "$APP/Contents/Resources/TextSwitcher_TextSwitcherCore.bundle"
swift scripts/icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.textswitcher.app "$APP"
print "Built: $APP"
