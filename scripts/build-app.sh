#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClipNest"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"
cp "${APP_NAME}/Info.plist" "${CONTENTS}/Info.plist"

ICON_SRC="${APP_NAME}/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"
if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${RESOURCES}/AppIcon.png"
    # Create icns if iconutil is available
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "${ICONSET_DIR}"
    for f in "${APP_NAME}"/Assets.xcassets/AppIcon.appiconset/icon_*.png; do
        cp "$f" "${ICONSET_DIR}/$(basename "$f")"
    done
    if command -v iconutil &>/dev/null; then
        iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES}/AppIcon.icns" 2>/dev/null && \
            echo "Created AppIcon.icns" || echo "Note: iconutil failed, using PNG icon"
    fi
fi

cat > "${CONTENTS}/PkgInfo" <<EOF
APPL????
EOF

echo "Created ${APP_BUNDLE}"
echo ""
echo "To install:"
echo "  cp -r ${APP_BUNDLE} /Applications/"
echo "  open /Applications/${APP_BUNDLE}"
