#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=0.1.3
BUILD=3
# Ad-hoc by default. Set SCREENTASK_SIGN_IDENTITY to a "Developer ID Application: ..." identity
# (security find-identity -v -p codesigning) to produce a distributable, hardened-runtime build,
# and SCREENTASK_NOTARY_PROFILE to a notarytool keychain profile to notarize and staple it.
IDENTITY="${SCREENTASK_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${SCREENTASK_NOTARY_PROFILE:-}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build -c release --arch arm64 --disable-sandbox
BIN_DIR=$(swift build -c release --arch arm64 --disable-sandbox --show-bin-path)
APP="$PWD/dist/ScreenTask Mac.app"
ZIP="$PWD/dist/ScreenTaskMac-$VERSION-arm64.zip"
if [ -d "$APP/ScreenTaskMac_ScreenTaskMac.bundle" ]; then
    rm -r "$APP/ScreenTaskMac_ScreenTaskMac.bundle"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ICONSET="$PWD/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 1024 1024 "$PWD/Assets/AppIcon-Source.png" --out "$PWD/.build/AppIcon.png" >/dev/null
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$PWD/.build/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$PWD/.build/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
test -s "$APP/Contents/Resources/AppIcon.icns"
echo 'ICON VERIFIED'
cp "$BIN_DIR/ScreenTaskMac" "$APP/Contents/MacOS/ScreenTaskMac"
# Place resources inside the signed app resource envelope.
cp -R "$BIN_DIR/ScreenTaskMac_ScreenTaskMac.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ScreenTaskMac</string>
<key>CFBundleIdentifier</key><string>io.github.AndyJuang.ScreenTaskMac</string>
<key>CFBundleName</key><string>ScreenTask Mac</string>
<key>CFBundleDisplayName</key><string>ScreenTask Mac</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>讓同一個區域網路的瀏覽器觀看您選擇分享的螢幕。</string>
<key>NSScreenCaptureUsageDescription</key><string>擷取您選擇的螢幕，供區域網路中的瀏覽器觀看。</string>
</dict></plist>
PLIST
if [ "$IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP"
    codesign --verify --deep --strict "$APP"
    echo 'SIGNED ad-hoc (not distributable: Gatekeeper will quarantine and translocate downloads)'
else
    # Sign inside out. --deep is not valid for Developer ID distribution.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/ScreenTaskMac_ScreenTaskMac.bundle"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    codesign --display --verbose=2 "$APP" 2>&1 | grep -q 'flags=.*runtime'
    echo "SIGNED $IDENTITY with hardened runtime"
fi
file "$APP/Contents/MacOS/ScreenTaskMac" | grep -q 'arm64'
plutil -lint "$APP/Contents/Info.plist"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=4 "$APP"
    # Re-package so the shipped archive carries the stapled ticket.
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    echo 'NOTARIZED AND STAPLED'
fi
(cd dist && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS.txt)
echo 'APP VERIFIED'
