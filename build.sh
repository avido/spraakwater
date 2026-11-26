#!/bin/bash
# Builds Spraakwater and assembles a signed .app bundle in build/Spraakwater.app.
#
# Usage:
#   ./build.sh            build only
#   ./build.sh install    build and copy to ~/Applications
#   ./build.sh run        build and start the app
#
# Signing uses a stable identity so the Accessibility and Keychain permissions
# survive rebuilds. Override with SIGN_IDENTITY="..." if needed.
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release

APP="build/Spraakwater.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Spraakwater "$APP/Contents/MacOS/Spraakwater"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/extince.png "$APP/Contents/Resources/extince.png"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep 'Apple Development' | head -1 | sed -E 's/.*"(.*)".*/\1/')}"
if [ -z "$IDENTITY" ]; then
    echo "No Apple Development identity found, falling back to ad-hoc signing (permissions reset on every build)."
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier nl.avido.spraakwater "$APP"
echo "Built $APP (signed with: $IDENTITY)"

case "${1:-}" in
    install)
        mkdir -p "$HOME/Applications"
        ditto "$APP" "$HOME/Applications/Spraakwater.app"
        echo "Installed to ~/Applications/Spraakwater.app"
        ;;
    run)
        open "$APP"
        ;;
esac
