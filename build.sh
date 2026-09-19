#!/bin/bash
set -e

# NoteBro Mac Build Pipeline
# Direct Distribution or MAS target

APP_NAME="NoteBro"
VERSION="1.0.0"
BUILD_NUMBER="1"
SRC_FILE="NoteBro.swift"
BUILD_DIR="build"
DIST_DIR="dist"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BIN_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

TARGET_MODE="${1:-direct}"

echo "🎨 Building ${APP_NAME} v${VERSION} (${TARGET_MODE} target)..."

# Clean previous build
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${BIN_DIR}" "${RES_DIR}" "${DIST_DIR}"

# 1. Compile Swift executable (Apple Silicon optimized)
SWIFT_FLAGS="-parse-as-library -O -target arm64-apple-macos13.0"
if [ "${TARGET_MODE}" = "mas" ]; then
    SWIFT_FLAGS="${SWIFT_FLAGS} -D MAS_BUILD"
fi
swiftc ${SWIFT_FLAGS} "${SRC_FILE}" -o "${BIN_DIR}/${APP_NAME}"

# 2. Generate Production Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.pibulus.notebro</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Pablo Alvarado. All rights reserved.</string>
</dict>
</plist>
PLIST

# 3. Copy Assets & AppIcon
cp Assets/*.png "${RES_DIR}/" 2>/dev/null || true
if [ -f "Assets/AppIcon.icns" ]; then
    cp Assets/AppIcon.icns "${RES_DIR}/"
fi

chmod +x "${BIN_DIR}/${APP_NAME}"

# 4. Code Signing (Secure Timestamp enabled)
ENTITLEMENTS="NoteBro.entitlements"

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
           | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)

if [ -n "${IDENTITY}" ]; then
    codesign --force --sign "${IDENTITY}" \
             --options runtime \
             --entitlements "${ENTITLEMENTS}" \
             --timestamp \
             --identifier com.pibulus.notebro "${BIN_DIR}/${APP_NAME}"
    codesign --force --sign "${IDENTITY}" \
             --options runtime \
             --entitlements "${ENTITLEMENTS}" \
             --timestamp \
             --identifier com.pibulus.notebro "${APP_DIR}"
    echo "🔏 Signed with Developer ID: ${IDENTITY}"
else
    codesign --force --sign - \
             --entitlements "${ENTITLEMENTS}" \
             --identifier com.pibulus.notebro "${BIN_DIR}/${APP_NAME}"
    codesign --force --sign - \
             --entitlements "${ENTITLEMENTS}" \
             --identifier com.pibulus.notebro "${APP_DIR}"
    echo "🔏 Ad-hoc signed for local execution"
fi

echo "✨ Built NoteBro.app at ${APP_DIR}"
