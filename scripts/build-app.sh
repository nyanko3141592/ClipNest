#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClipNest"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Building release..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"
cp "${APP_NAME}/Info.plist" "${CONTENTS}/Info.plist"

# --- Icon ---
ICON_SRC="${APP_NAME}/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"
if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${RESOURCES}/AppIcon.png"
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "${ICONSET_DIR}"
    # iconutil requires specific naming: icon_<size>x<size>[@2x].png
    for f in "${APP_NAME}"/Assets.xcassets/AppIcon.appiconset/icon_*.png; do
        cp "$f" "${ICONSET_DIR}/$(basename "$f")"
    done
    if command -v iconutil &>/dev/null; then
        iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES}/AppIcon.icns" 2>/dev/null && \
            echo "    Created AppIcon.icns" || echo "    Note: iconutil failed, using PNG icon"
    fi
fi

cat > "${CONTENTS}/PkgInfo" <<'EOF'
APPL????
EOF

# --- Ad-hoc codesign ---
echo "==> Signing app bundle (ad-hoc)..."
codesign --force --deep --sign - \
    --options runtime \
    --entitlements /dev/stdin \
    "${APP_BUNDLE}" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
ENTITLEMENTS

codesign --verify --deep --strict "${APP_BUNDLE}" && \
    echo "    Signature verified" || echo "    WARNING: Signature verification failed"

# --- Package as DMG ---
echo "==> Creating DMG..."
DMG_NAME="${APP_NAME}.dmg"
DMG_TEMP="dmg_tmp"
rm -rf "${DMG_TEMP}" "${DMG_NAME}"
mkdir -p "${DMG_TEMP}"
cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_NAME}" \
    > /dev/null

rm -rf "${DMG_TEMP}"
echo "    Created ${DMG_NAME}"

# --- Package as zip (using ditto to preserve macOS metadata) ---
echo "==> Creating zip..."
ZIP_NAME="${APP_NAME}.zip"
rm -f "${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_NAME}"
echo "    Created ${ZIP_NAME}"

echo ""
echo "==> Done!"
echo "  ${APP_BUNDLE}  — app bundle"
echo "  ${DMG_NAME}     — DMG (drag & drop install)"
echo "  ${ZIP_NAME}     — zip archive"
echo ""
echo "To install:"
echo "  cp -r ${APP_BUNDLE} /Applications/"
echo ""
echo "NOTE: ダウンロードしたファイルで「壊れている」と表示される場合:"
echo "  xattr -cr /Applications/${APP_BUNDLE}"
