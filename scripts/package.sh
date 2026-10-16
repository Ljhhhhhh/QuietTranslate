#!/bin/zsh
# 生成应用与拖放安装 DMG（ad-hoc 签名，仅供本机使用）。
set -e
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)/QuietTranslate
APP=build/QuietTranslate.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R "$(dirname "$BIN")/QuietTranslate_QuietTranslate.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.quiettranslate</string>
<key>CFBundleName</key><string>QuietTranslate</string>
<key>CFBundleExecutable</key><string>QuietTranslate</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P
codesign --force --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
STAGING=$(mktemp -d "${TMPDIR%/}/QuietTranslate.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/QuietTranslate.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname QuietTranslate -srcfolder "$STAGING" -format UDZO -ov build/QuietTranslate.dmg
echo "$APP"
echo "build/QuietTranslate.dmg"
