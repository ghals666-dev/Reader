#!/bin/bash
# Reader.app 묶음과 reader-cli를 build/ 아래에 만든다. (macOS에서 실행)
set -euo pipefail
cd "$(dirname "$0")/.."

# 애플 실리콘과 인텔 맥 모두에서 도는 유니버설 바이너리로 만든다.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product ReaderApp
swift build -c release "${ARCHS[@]}" --product reader-cli
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/Reader.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ReaderApp" "$APP/Contents/MacOS/Reader"
cp "$BIN_DIR/reader-cli" build/reader-cli

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Reader</string>
    <key>CFBundleDisplayName</key><string>Reader</string>
    <key>CFBundleIdentifier</key><string>dev.reader.pdf2txt</string>
    <key>CFBundleExecutable</key><string>Reader</string>
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
lipo -archs "$APP/Contents/MacOS/Reader"
(cd build && ditto -c -k --keepParent Reader.app Reader.zip)
echo "완성: $APP, build/Reader.zip, build/reader-cli"
