#!/bin/zsh
# 生成应用与拖放安装 DMG，始终复用稳定的签名身份。
set -eu
cd "$(dirname "$0")/.."
IDENTITY=${CODE_SIGN_IDENTITY:-QuietTranslate Local Signing}
if [[ "$IDENTITY" == '-' ]]; then
    echo '不能使用 ad-hoc 签名：它会导致更新后授权失效。' >&2
    exit 1
fi
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo '缺少签名证书。首次本机构建请执行：zsh scripts/setup-signing.sh' >&2
    echo '已有安装请恢复原证书和私钥，不要重新生成签名身份。' >&2
    exit 1
fi
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
codesign --force --sign "$IDENTITY" "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
REQUIREMENT=$(codesign -d -r- "$APP" 2>&1)
if [[ "$REQUIREMENT" != *'certificate'* || "$REQUIREMENT" == *'designated => cdhash'* ]]; then
    echo '签名未生成稳定的证书身份，停止打包。' >&2
    exit 1
fi
STAGING=$(mktemp -d "${TMPDIR%/}/QuietTranslate.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/QuietTranslate.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname QuietTranslate -srcfolder "$STAGING" -format UDZO -ov build/QuietTranslate.dmg
echo "$APP"
echo "build/QuietTranslate.dmg"
