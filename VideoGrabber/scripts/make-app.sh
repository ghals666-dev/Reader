#!/bin/bash
# VideoGrabber.app을 build/ 아래에 만든다. (macOS에서 실행)
# yt-dlp 유니버설 바이너리를 앱 안에 함께 넣는다. ffmpeg 정적 빌드도 함께 넣는다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="build/VideoGrabber.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/VideoGrabber" "$APP/Contents/MacOS/VideoGrabber"

curl -fL --retry 3 -o "$APP/Contents/Resources/yt-dlp" \
  https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos
chmod +x "$APP/Contents/Resources/yt-dlp"

# ffmpeg: Apple 실리콘·인텔 정적 빌드를 받아 유니버설 하나로 합친다. 받기에 실패하면 빌드도 실패한다.
FF_BASE=https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1
FF_TMP="$(mktemp -d)"
curl -fL --retry 3 -o "$FF_TMP/arm.gz" "$FF_BASE/ffmpeg-darwin-arm64.gz"
curl -fL --retry 3 -o "$FF_TMP/x64.gz" "$FF_BASE/ffmpeg-darwin-x64.gz"
gunzip -c "$FF_TMP/arm.gz" > "$FF_TMP/ffmpeg-arm"
gunzip -c "$FF_TMP/x64.gz" > "$FF_TMP/ffmpeg-x64"
lipo -create "$FF_TMP/ffmpeg-arm" "$FF_TMP/ffmpeg-x64" -output "$APP/Contents/Resources/ffmpeg"
chmod +x "$APP/Contents/Resources/ffmpeg"
codesign --force -s - "$APP/Contents/Resources/ffmpeg"   # lipo가 서명을 지우므로 다시 서명
echo "ffmpeg 포함: $(lipo -archs "$APP/Contents/Resources/ffmpeg")"
rm -rf "$FF_TMP"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>VideoGrabber</string>
    <key>CFBundleDisplayName</key><string>VideoGrabber</string>
    <key>CFBundleIdentifier</key><string>dev.reader.videograbber</string>
    <key>CFBundleExecutable</key><string>VideoGrabber</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
(cd build && ditto -c -k --keepParent VideoGrabber.app VideoGrabber.zip)
echo "완성: $APP, build/VideoGrabber.zip"
