#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "🔨 Building Sokovia binary..."
swift build -c release

BIN_PATH="$(find .build -name Sokovia -type f -perm +111 | grep -i "release/Sokovia" | head -n 1)"
if [ -z "$BIN_PATH" ]; then
    BIN_PATH=".build/out/Products/Release/Sokovia"
fi

APP_BUNDLE="$DIR/Sokovia.app"
echo "📦 Packaging into $APP_BUNDLE..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/Sokovia"
chmod +x "$APP_BUNDLE/Contents/MacOS/Sokovia"
if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Sokovia</string>
    <key>CFBundleExecutable</key>
    <string>Sokovia</string>
    <key>CFBundleIdentifier</key>
    <string>com.sokovia.drive</string>
    <key>CFBundleName</key>
    <string>Sokovia</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Sokovia. All rights reserved.</string>
</dict>
</plist>
EOF

echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✅ Sokovia.app successfully created at $APP_BUNDLE"

