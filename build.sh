#!/bin/bash
# Builds Dicteer and assembles a signed .app bundle in build/Dicteer.app.
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

APP="build/Dicteer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Dicteer "$APP/Contents/MacOS/Dicteer"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep 'Apple Development' | head -1 | sed -E 's/.*"(.*)".*/\1/')}"
if [ -z "$IDENTITY" ]; then
    echo "No Apple Development identity found, falling back to ad-hoc signing (permissions reset on every build)."
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier nl.avido.dicteer "$APP"
echo "Built $APP (signed with: $IDENTITY)"

case "${1:-}" in
    install)
        mkdir -p "$HOME/Applications"
        ditto "$APP" "$HOME/Applications/Dicteer.app"
        echo "Installed to ~/Applications/Dicteer.app"
        ;;
    run)
        open "$APP"
        ;;
esac
