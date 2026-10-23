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
VERSION=$(cat VERSION)
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo 'VERSION 必须为三段数字版本号，例如 1.2.3。' >&2
    exit 1
fi
if [[ ! -s Resources/UpdatePublicKey.txt ]]; then
    echo '缺少更新公钥。首次构建请执行：zsh scripts/setup-updates.sh' >&2
    exit 1
fi
swift build -c release
BIN=$(swift build -c release --show-bin-path)/QuietTranslate
TOOLS=.build/artifacts/sparkle/Sparkle/bin
PUBLIC_KEY=$(cat Resources/UpdatePublicKey.txt)
if [[ "$("$TOOLS/generate_keys" --account local.quiettranslate.sparkle -p)" != "$PUBLIC_KEY" ]]; then
    echo '更新签名密钥与应用公钥不一致，停止打包。' >&2
    exit 1
fi
APP=build/QuietTranslate.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/"
cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/"
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
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>SUFeedURL</key><string>https://github.com/Ljhhhhhh/QuietTranslate/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for COMPONENT in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/$COMPONENT"
done
codesign --force --sign "$IDENTITY" "$FRAMEWORK"
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
mkdir -p "$STAGING/updates"
cp build/QuietTranslate.dmg "$STAGING/updates/QuietTranslate-$VERSION.dmg"
"$TOOLS/generate_appcast" --account local.quiettranslate.sparkle --maximum-deltas 0 \
    --download-url-prefix "https://github.com/Ljhhhhhh/QuietTranslate/releases/download/v$VERSION/" "$STAGING/updates"
SIGNATURE=$(/usr/bin/xmllint --xpath 'string(//enclosure/@*[local-name()="edSignature"])' "$STAGING/updates/appcast.xml")
"$TOOLS/sign_update" --account local.quiettranslate.sparkle --verify \
    "$STAGING/updates/QuietTranslate-$VERSION.dmg" "$SIGNATURE"
mkdir -p build/updates
cp "$STAGING/updates/QuietTranslate-$VERSION.dmg" "$STAGING/updates/appcast.xml" build/updates/
echo "$APP"
echo "build/QuietTranslate.dmg"
echo "build/updates/QuietTranslate-$VERSION.dmg"
echo 'build/updates/appcast.xml'
