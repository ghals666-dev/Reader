#!/bin/bash
# VideoGrabber.app을 build/ 아래에 만든다. (macOS에서 실행)
# yt-dlp 유니버설 바이너리를 앱 안에 함께 넣는다. ffmpeg는 있으면 Homebrew 것을 쓴다.
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

# ffmpeg: Intel(evermeet)과 Apple 실리콘(osxexperts) 정적 빌드를 받아 유니버설로 합친다. 실패하면 건너뛴다.
FF_TMP="$(mktemp -d)"
if curl -fL --retry 3 -o "$FF_TMP/x86.zip" https://evermeet.cx/ffmpeg/getrelease/zip \
   && curl -fL --retry 3 -o "$FF_TMP/arm.zip" https://www.osxexperts.net/ffmpeg7arm.zip \
   && unzip -q -o "$FF_TMP/x86.zip" -d "$FF_TMP/x86" && unzip -q -o "$FF_TMP/arm.zip" -d "$FF_TMP/arm" \
   && lipo -create "$FF_TMP/x86/ffmpeg" "$FF_TMP/arm/ffmpeg" -output "$APP/Contents/Resources/ffmpeg"; then
  chmod +x "$APP/Contents/Resources/ffmpeg"
  echo "ffmpeg 포함: $(lipo -archs "$APP/Contents/Resources/ffmpeg")"
else
  echo "경고: ffmpeg를 받지 못해 앱에 넣지 않았습니다. (brew install ffmpeg로 대신할 수 있습니다)"
fi
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
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
(cd build && ditto -c -k --keepParent VideoGrabber.app VideoGrabber.zip)
echo "완성: $APP, build/VideoGrabber.zip"
