# VideoGrabber

인터넷 동영상 주소를 붙여 넣으면 맥에 저장해 주는 앱입니다. 내부적으로 [yt-dlp](https://github.com/yt-dlp/yt-dlp)를 씁니다.
본인이 받을 권리가 있는 영상에만 사용하세요.

## 쓰는 법
1. 주소를 붙여 넣습니다. (여러 개는 줄바꿈으로 구분)
2. 형식(영상 mp4 / 음원 mp3)과 저장 폴더를 고릅니다.
3. 다운로드(⌘Return)를 누릅니다.

mp3 변환과 고화질 영상·음성 합치기에는 ffmpeg가 필요합니다: `brew install ffmpeg`
(없으면 단일 파일 mp4로 받습니다.)

## 빌드 (macOS)
```bash
scripts/make-app.sh   # build/VideoGrabber.app, build/VideoGrabber.zip
```
서명이 없는 앱이라 처음에는 `xattr -dr com.apple.quarantine VideoGrabber.app`가 필요합니다.
yt-dlp는 사이트 변경으로 자주 깨지니, 다운로드가 실패하면 앱을 새로 빌드해 최신 yt-dlp를 넣으세요.
