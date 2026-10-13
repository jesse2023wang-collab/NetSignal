#!/bin/bash
set -e

echo "Building NetSignal..."
swift build --disable-sandbox -c release

VERSION="1.0.3"
STAGING=$(mktemp -d)

echo "Creating app bundle..."
mkdir -p NetSignal.app/Contents/MacOS
cp .build/release/NetSignal NetSignal.app/Contents/MacOS/NetSignal
chmod +x NetSignal.app/Contents/MacOS/NetSignal

# Create Info.plist (required for macOS app bundle)
cat > "NetSignal.app/Contents/Info.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>NetSignal</string>
	<key>CFBundleExecutable</key>
	<string>NetSignal</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.netsignal.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>NetSignal</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>VERSION_PLACEHOLDER</string>
	<key>CFBundleVersion</key>
	<string>VERSION_PLACEHOLDER</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2025 NetSignal. All rights reserved.</string>
</dict>
</plist>
PLIST_EOF

# Replace version placeholder
sed -i '' "s/VERSION_PLACEHOLDER/${VERSION}/g" "NetSignal.app/Contents/Info.plist"

# Generate icons if not exists
if [ ! -f "Resources/AppIcon.icns" ] || [ ! -f "Resources/AppIcon.png" ]; then
    echo "Generating icons..."
    python3 generate_icon.py || { echo "Icon generation failed, continuing without icon"; exit 0; }
fi

mkdir -p "NetSignal.app/Contents/Resources"

# Copy icon files to app bundle
cp Resources/AppIcon.icns "NetSignal.app/Contents/Resources/"
cp Resources/AppIcon.png "NetSignal.app/Contents/Resources/"

# 代码签名（ad-hoc，避免 Gatekeeper 报"文件已损坏"）
echo "Signing app bundle..."
codesign --force --deep --sign - "NetSignal.app" || echo "Warning: codesign failed, app may show 'damaged' on other Macs"

# Copy complete app to staging for DMG
cp -R NetSignal.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Creating DMG: NetSignal-${VERSION}.dmg..."
hdiutil create -volname "NetSignal ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "NetSignal-${VERSION}.dmg"
rm -rf "$STAGING"

# Clean up intermediate artifacts
rm -rf NetSignal.app

echo "Build complete!"
echo ""
echo "DMG available at: $(pwd)/NetSignal-${VERSION}.dmg"
