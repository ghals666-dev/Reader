# VideoGrabber

메뉴바에 사는 동영상 다운로드 앱입니다. 내부적으로 [yt-dlp](https://github.com/yt-dlp/yt-dlp)를 씁니다.
본인이 받을 권리가 있는 영상에만 사용하세요.

## 쓰는 법
1. 영상이 있는 페이지 주소를 복사합니다.
2. 메뉴바의 ⬇︎ 아이콘을 누르면 클립보드 주소가 자동으로 들어가고 영상 정보를 조회합니다.
3. 화질 목록에서 고르고 다운로드(Return)를 누릅니다. 기본 저장 폴더는 다운로드입니다.

- **ffmpeg:** `brew install ffmpeg`로 설치해 두세요. 앱이 `/opt/homebrew/bin`, `/usr/local/bin`에서 자동으로 찾습니다. 없으면 단일 파일 mp4만 받아 고화질이 제한됩니다.
- **로그인 필요한 영상:** 쿠키 메뉴에서 브라우저를 고르세요. Safari는 앱에 전체 디스크 접근 권한이 필요합니다.
- **yt-dlp 갱신:** 창 아래 「yt-dlp 갱신」 버튼이 최신 버전을 `~/Library/Application Support/VideoGrabber/`에 받아 우선 사용합니다.
- 다운로드가 끝나거나 실패하면 알림이 뜹니다.
일반 웹페이지는 yt-dlp의 범용 추출기에 의존하므로, 페이지에 따라 영상을 못 찾을 수 있습니다.

## 빌드 (macOS)
```bash
scripts/make-app.sh   # build/VideoGrabber.app, build/VideoGrabber.zip
```
서명이 없는 앱이라 처음에는 `xattr -dr com.apple.quarantine VideoGrabber.app`가 필요합니다.
yt-dlp는 사이트 변경으로 자주 깨지니, 실패하면 앱을 새로 빌드해 최신 yt-dlp를 넣으세요.
