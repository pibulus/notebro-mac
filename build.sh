#!/bin/bash
set -e

# NoteBro Mac Build Pipeline
# Direct Distribution or MAS target

APP_NAME="NoteBro"
VERSION="1.1.0"
BUILD_NUMBER="1"
SRC_FILES="NoteBroModel.swift NoteBro.swift NoteBroVaultSync.swift"
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
swiftc ${SWIFT_FLAGS} ${SRC_FILES} -o "${BIN_DIR}/${APP_NAME}"

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
if [ "${TARGET_MODE}" = "mas" ]; then
    ENTITLEMENTS="NoteBro-MAS.entitlements"
else
    ENTITLEMENTS="NoteBro.entitlements"
fi

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

# 5. Build DMG for Direct Distribution
echo "💿 Creating DMG disk image..."
DMG_STAGE="${BUILD_DIR}/dmg_stage"
mkdir -p "${DMG_STAGE}"
cp -R "${APP_DIR}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${DMG_STAGE}" \
        -ov -format UDZO \
        "${DIST_DIR}/${APP_NAME}-${VERSION}.dmg" > /dev/null
        
rm -rf "${DMG_STAGE}"

# Sign the DMG disk image container
if [ -n "${IDENTITY}" ]; then
    codesign --force --sign "${IDENTITY}" --timestamp "${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
    echo "🔏 Signed DMG container with Developer ID: ${IDENTITY}"
fi

# 6. Notarize & staple. Without this, Gatekeeper rejects the download for
#    everyone who isn't the machine that built it ("Unnotarized Developer ID").
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "⏭️  Skipping notarization (SKIP_NOTARIZE=1)."
elif [ -z "${IDENTITY}" ]; then
    echo "⚠️  Ad-hoc signed — nothing to notarize."
elif xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "🔐 Submitting DMG for notarization (profile: ${NOTARY_PROFILE})…"
    if xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait; then
        echo "📎 Stapling notarization ticket…"
        xcrun stapler staple "${DMG_PATH}"
        echo "✅ Notarized & stapled: ${DMG_PATH}"
    else
        echo "❌ Notarization failed. DMG is signed but NOT notarized."
    fi
else
    echo "⚠️  Notary profile '${NOTARY_PROFILE}' not found — skipping notarization."
    echo "    Create it once with:"
    echo "      xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\"
    echo "        --apple-id <apple-id-email> --team-id V433H655PN --password <app-specific-password>"
fi

echo "✨ Direct DMG ready at ${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
echo "✨ Built NoteBro.app at ${APP_DIR}"

