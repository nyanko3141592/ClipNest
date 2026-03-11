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

if [ -d "${APP_NAME}/Assets.xcassets" ]; then
    echo "Note: Asset catalog compilation requires Xcode tools."
    echo "      App will use system SF Symbol for menu bar icon."
fi

cat > "${CONTENTS}/PkgInfo" <<EOF
APPL????
EOF

echo "Created ${APP_BUNDLE}"
echo ""
echo "To install:"
echo "  cp -r ${APP_BUNDLE} /Applications/"
echo "  open /Applications/${APP_BUNDLE}"
