#!/bin/bash
# Build, bundle, sign and package RepoSentinel.
#   SIGN_ID="Developer ID Application: Name (TEAMID)"  ./scripts/build.sh      # signed for distribution
#   NOTARY_PROFILE=my-profile                                                  # also notarize + staple (see README)
# With no SIGN_ID the app is ad-hoc signed (runs on this Mac; other Macs need right-click → Open).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"; BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/' || true)}"
SIGN_ID="${SIGN_ID:--}"
APP=dist/RepoSentinel.app
swift test 2>&1 | tail -2
swift build -c release --arch arm64
rm -rf dist; mkdir -p $APP/Contents/{MacOS,Resources}
cp "$(swift build -c release --arch arm64 --show-bin-path)/RepoSentinel" $APP/Contents/MacOS/
swift scripts/make_icon.swift dist/AppIcon.iconset && iconutil -c icns dist/AppIcon.iconset -o $APP/Contents/Resources/AppIcon.icns && rm -rf dist/AppIcon.iconset
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RepoSentinel</string>
<key>CFBundleIdentifier</key><string>com.akhlaq.reposentinel</string>
<key>CFBundleName</key><string>RepoSentinel</string>
<key>CFBundleDisplayName</key><string>RepoSentinel</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>© 2026 Akhlaq Ahmad</string>
<key>NSDocumentsFolderUsageDescription</key><string>RepoSentinel reads your repositories to look for malware. Nothing is modified or uploaded.</string>
<key>NSDesktopFolderUsageDescription</key><string>RepoSentinel reads your repositories to look for malware. Nothing is modified or uploaded.</string>
<key>NSDownloadsFolderUsageDescription</key><string>RepoSentinel reads your repositories to look for malware. Nothing is modified or uploaded.</string>
<key>NSRemovableVolumesUsageDescription</key><string>RepoSentinel reads repositories on external drives to look for malware.</string>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" $APP 2>&1 | tail -1
[ "$SIGN_ID" != "-" ] && codesign --force --options runtime --timestamp --sign "$SIGN_ID" $APP
codesign --verify --strict --verbose=1 $APP 2>&1 | tail -1
# DMG with an Applications shortcut
STAGE=$(mktemp -d); cp -R $APP "$STAGE/"; ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "RepoSentinel $VERSION" -srcfolder "$STAGE" -ov -format UDZO "dist/RepoSentinel-$VERSION.dmg"; rm -rf "$STAGE"
if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_ID" != "-" ]; then
  xcrun notarytool submit "dist/RepoSentinel-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/RepoSentinel-$VERSION.dmg"
fi
echo "Built $APP (signed as: $SIGN_ID) and dist/RepoSentinel-$VERSION.dmg"
