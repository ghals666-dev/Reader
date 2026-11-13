import XCTest
@testable import ReaderCore

final class CoreTests: XCTestCase {
    let rowH = 0.022
    let pitch = 0.036
    let pageH = 1.4

    func line(_ text: String, x: Double, to maxX: Double, y: Double) -> TextLine {
        TextLine(text: text, box: Rect(x: x, y: y, width: maxX - x, height: rowH))
    }

    func plain() -> BuildOptions { BuildOptions(pageMarkers: false, structureMarkers: true) }

    // MARK: 쪽번호·머리글

    func testPageNumberParsing() {
        XCTAssertEqual(HeaderFooterFilter.pageNumber(in: "126 / 179"), 126)
        XCTAssertEqual(HeaderFooterFilter.pageNumber(in: "- 12 -"), 12)
        XCTAssertEqual(HeaderFooterFilter.pageNumber(in: "7"), 7)
        XCTAssertNil(HeaderFooterFilter.pageNumber(in: "3장 여름"))
        XCTAssertNil(HeaderFooterFilter.pageNumber(in: "12345"))
    }

    func testHeaderFooterRemovedAndPrintedNumbersUsed() {
        var pages: [RawPage] = []
        for i in 0..<3 {
            pages.append(RawPage(index: i, height: pageH, lines: [
                line("3장 여름 이야기", x: 0.4, to: 0.6, y: 0.04),
                line("본문 \(i) 첫째 줄은 끝까지 차 있고", x: 0.05, to: 0.95, y: 0.30),
                line("둘째 줄에서 끝납니다.", x: 0.05, to: 0.50, y: 0.336),
                line("\(126 + i) / 179", x: 0.45, to: 0.55, y: 1.34),
            ], source: .ocr))
        }
        let text = DocumentBuilder.build(pages: pages).text
        XCTAssertFalse(text.contains("여름 이야기"), text)
        XCTAssertFalse(text.contains("179"), text)
        XCTAssertTrue(text.contains("[p.126]"), text)
        XCTAssertTrue(text.contains("[p.128]"), text)
        XCTAssertTrue(text.contains("본문 1 첫째 줄은"), text)
    }

    func testBodyLineNearTopIsKept() {
        // 위쪽 구역에 있어도 이웃 쪽에서 반복되지 않으면 본문이다.
        let pages = (0..<2).map { i in
            RawPage(index: i, height: pageH, lines: [
                line("쪽마다 다른 첫 줄 \(i == 0 ? "하나" : "둘셋넷")", x: 0.05, to: 0.95, y: 0.08),
                line("이어지는 줄입니다.", x: 0.05, to: 0.5, y: 0.116),
            ], source: .ocr)
        }
        let text = DocumentBuilder.build(pages: pages, options: plain()).text
        XCTAssertTrue(text.contains("하나"), text)
        XCTAssertTrue(text.contains("둘셋넷"), text)
    }

    // MARK: 단

    func testTwoColumnsReadLeftThenRight() {
        var lines: [TextLine] = []
        for r in 0..<6 {
            let y = 0.2 + Double(r) * pitch
            // 같은 높이의 오른쪽 줄을 먼저 넣어 순서에 기대지 않게 한다.
            lines.append(line("R\(r + 1)", x: 0.53, to: 0.95, y: y))
            lines.append(line("L\(r + 1)", x: 0.05, to: 0.47, y: y))
        }
        let page = RawPage(index: 0, height: pageH, lines: lines, source: .ocr)
        let text = DocumentBuilder.build(pages: [page], options: plain()).text
        let order = ["L1", "L2", "L3", "L4", "L5", "L6", "R1", "R2", "R3", "R4", "R5", "R6"]
        var cursor = text.startIndex
        for token in order {
            guard let found = text.range(of: token, range: cursor..<text.endIndex) else {
                return XCTFail("\(token) 순서가 어긋남: \(text)")
            }
            cursor = found.upperBound
        }
    }

    func testSingleColumnIsNotSplit() {
        let lines = (0..<8).map { r in
            line("W\(r)", x: 0.05, to: 0.95, y: 0.2 + Double(r) * pitch)
        }
        XCTAssertNil(ColumnLayout.findGutter(lines))
    }

    func testTitleAboveTwoColumnsComesFirst() {
        var lines = [line("TITLE", x: 0.2, to: 0.8, y: 0.1)]
        for r in 0..<5 {
            let y = 0.2 + Double(r) * pitch
            lines.append(line("L\(r)", x: 0.05, to: 0.47, y: y))
            lines.append(line("R\(r)", x: 0.53, to: 0.95, y: y))
        }
        let segments = ColumnLayout.segments(for: lines)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.first?.rows.first?.text, "TITLE")
        XCTAssertEqual(segments[1].rows.first?.text, "L0")
        XCTAssertEqual(segments[2].rows.first?.text, "R0")
    }

    // MARK: 문단

    func testParagraphJoinAndIndentSplit() {
        let page = RawPage(index: 0, height: pageH, lines: [
            line("가나다라 마바사", x: 0.05, to: 0.95, y: 0.200),
            line("아자차카.", x: 0.05, to: 0.50, y: 0.236),
            line("둘째 문단의 시작", x: 0.07, to: 0.95, y: 0.272),
            line("부분입니다.", x: 0.05, to: 0.40, y: 0.308),
        ], source: .ocr)
        let text = DocumentBuilder.build(pages: [page], options: plain()).text
        XCTAssertEqual(text, "가나다라 마바사아자차카.\n\n둘째 문단의 시작부분입니다.\n")
    }

    func testShortLineWithoutPeriodKeepsLineBreak() {
        let page = RawPage(index: 0, height: pageH, lines: [
            line("첫 항목", x: 0.05, to: 0.30, y: 0.200),
            line("둘째 항목", x: 0.05, to: 0.32, y: 0.236),
            line("이 줄은 오른쪽 끝까지 가득 차 있습니다", x: 0.05, to: 0.95, y: 0.272),
            line("마지막.", x: 0.05, to: 0.20, y: 0.308),
        ], source: .ocr)
        let text = DocumentBuilder.build(pages: [page], options: plain()).text
        XCTAssertTrue(text.contains("첫 항목\n둘째 항목\n"), text)
    }

    func testParagraphContinuesAcrossPagesAndMarkerWaits() {
        let p1 = RawPage(index: 0, height: pageH, lines: [
            line("첫 쪽의 글은 여기서 시작하여", x: 0.05, to: 0.95, y: 0.200),
            line("다음 쪽으로 넘어가는데 정말 대단히", x: 0.05, to: 0.95, y: 0.236),
        ], source: .ocr)
        let p2 = RawPage(index: 1, height: pageH, lines: [
            line("길게 이어집니다.", x: 0.05, to: 0.40, y: 0.200),
            line("새 문단입니다.", x: 0.07, to: 0.40, y: 0.236),
        ], source: .ocr)
        let text = DocumentBuilder.build(pages: [p1, p2]).text
        XCTAssertTrue(text.contains("정말 대단히 길게 이어집니다."), text)
        guard let marker = text.range(of: "[p.2]"),
              let joined = text.range(of: "길게 이어집니다."),
              let fresh = text.range(of: "새 문단입니다.") else {
            return XCTFail(text)
        }
        XCTAssertTrue(joined.upperBound <= marker.lowerBound, text)
        XCTAssertTrue(marker.upperBound <= fresh.lowerBound, text)
    }

    func testHeadingAndQuoteMarkers() {
        let page = RawPage(index: 0, height: pageH, lines: [
            line("본문 첫 줄은 오른쪽 끝까지 이어지고", x: 0.05, to: 0.95, y: 0.100),
            line("여기서 끝납니다.", x: 0.05, to: 0.50, y: 0.136),
            line("작은 제목 하나", x: 0.40, to: 0.60, y: 0.230),
            line("제목 아래 본문도 끝까지 이어지고", x: 0.05, to: 0.95, y: 0.320),
            line("한 줄 더 끝까지 이어진 다음", x: 0.05, to: 0.95, y: 0.356),
            line("끝납니다.", x: 0.05, to: 0.30, y: 0.392),
            line("인용한 글의 첫 줄은 길고", x: 0.07, to: 0.95, y: 0.480),
            line("둘째 줄도 마찬가지로 길며", x: 0.07, to: 0.95, y: 0.516),
            line("여기서 맺습니다.", x: 0.07, to: 0.50, y: 0.552),
        ], source: .ocr)
        let text = DocumentBuilder.build(pages: [page], options: plain()).text
        XCTAssertTrue(text.contains("\n\n## 작은 제목 하나\n\n"), text)
        XCTAssertTrue(text.contains("\n\n> 인용한 글의 첫 줄은"), text)

        let bare = DocumentBuilder.build(
            pages: [page], options: BuildOptions(pageMarkers: false, structureMarkers: false)).text
        XCTAssertFalse(bare.contains("##"), bare)
        XCTAssertFalse(bare.contains("> "), bare)
        XCTAssertTrue(bare.contains("작은 제목 하나"), bare)
    }

    // MARK: 줄 잇기

    func testKoreanLineJoining() {
        // 조사·어미로 시작하면 붙인다
        XCTAssertEqual(LineJoiner.join("우리 학교", "는 언덕 위에 있다"), "우리 학교는 언덕 위에 있다")
        XCTAssertEqual(LineJoiner.join("천천히 걸어갔습", "니다. 그리고"), "천천히 걸어갔습니다. 그리고")
        // 앞 낱말이 끝난 모양이면 띄운다
        XCTAssertEqual(LineJoiner.join("나무를 심었다는", "소식을 들었다"), "나무를 심었다는 소식을 들었다")
        // 근거가 없으면 붙인다(낱말 중간에서 끊긴 경우가 더 흔하다)
        XCTAssertEqual(LineJoiner.join("오래된 박물", "관에 갔다"), "오래된 박물관에 갔다")
        // 닫는 따옴표 뒤의 조사
        XCTAssertEqual(LineJoiner.join("“어서 오세요”", "라는 인사"), "“어서 오세요”라는 인사")
        XCTAssertEqual(LineJoiner.join("“어서 오세요”", "하늘이 맑았다"), "“어서 오세요” 하늘이 맑았다")
        // 영문
        XCTAssertEqual(LineJoiner.join("hello", "world"), "hello world")
        XCTAssertEqual(LineJoiner.join("inter-", "national"), "international")
        XCTAssertEqual(LineJoiner.join("끝났다.", "다음 문장"), "끝났다. 다음 문장")
    }

    func testKoreanLineJoiningParticlesAndStandaloneWords() {
        // 한 글자 어미
        XCTAssertEqual(LineJoiner.join("집에 가면", "서 쉬었다"), "집에 가면서 쉬었다")
        XCTAssertEqual(LineJoiner.join("힘을 얻는", "다. 그리고"), "힘을 얻는다. 그리고")
        XCTAssertEqual(LineJoiner.join("그렇게 말하지", "요(웃음)"), "그렇게 말하지요(웃음)")
        // 복수 '들' 뒤
        XCTAssertEqual(LineJoiner.join("마을 사람들", "이 모였다"), "마을 사람들이 모였다")
        XCTAssertEqual(LineJoiner.join("마을 사람들", "모두 모였다"), "마을 사람들 모두 모였다")
        // 홀로 쓰는 낱말 뒤
        XCTAssertEqual(LineJoiner.join("서로를 위해", "노래했다"), "서로를 위해 노래했다")
        XCTAssertEqual(LineJoiner.join("일을 계속", "이어 갔다"), "일을 계속 이어 갔다")
        XCTAssertEqual(LineJoiner.join("끝까지 가도록", "도왔다"), "끝까지 가도록 도왔다")
        // '하다' 꼴
        XCTAssertEqual(LineJoiner.join("열심히 공부", "했다"), "열심히 공부했다")
        XCTAssertEqual(LineJoiner.join("어제 숙제를", "했다"), "어제 숙제를 했다")
        XCTAssertEqual(LineJoiner.join("날마다 기도", "하였다"), "날마다 기도하였다")
        XCTAssertEqual(LineJoiner.join("어제 숙제를", "하였다"), "어제 숙제를 하였다")
        // 붙여 쓰는 짝과 홀로 쓰는 말머리
        XCTAssertEqual(LineJoiner.join("정말 너무", "나도 좋았다"), "정말 너무나도 좋았다")
        XCTAssertEqual(LineJoiner.join("정말 너무", "힘들었다"), "정말 너무 힘들었다")
        XCTAssertEqual(LineJoiner.join("그 말", "역시 옳았다"), "그 말 역시 옳았다")
        XCTAssertEqual(LineJoiner.join("그렇게 하시되", "천천히 하세요"), "그렇게 하시되 천천히 하세요")
        XCTAssertEqual(LineJoiner.join("집이 오래되", "었다"), "집이 오래되었다")
    }

    func testNoiseCleaning() {
        XCTAssertEqual(NoiseCleaner.clean("그렇습니다.3 다음 문장"), "그렇습니다. 다음 문장")
        XCTAssertEqual(NoiseCleaner.clean("좋은 것”4이라고 했다"), "좋은 것”이라고 했다")
        XCTAssertEqual(NoiseCleaner.clean("끝입니다.12"), "끝입니다.")
        XCTAssertEqual(NoiseCleaner.clean("먼저 ·•(여럿) 그리고 •··."), "먼저 …(여럿) 그리고 ….")
        XCTAssertEqual(NoiseCleaner.clean("그런 것 같아요.® 다음"), "그런 것 같아요. 다음")
        XCTAssertEqual(NoiseCleaner.clean("그렇게 말합니다.? 다음"), "그렇게 말합니다. 다음")
        XCTAssertEqual(NoiseCleaner.clean("정말입니까? 네."), "정말입니까? 네.")
        // 숫자가 내용인 경우는 그대로
        XCTAssertEqual(NoiseCleaner.clean("2012년 3월에 1.2 판이 나왔다."), "2012년 3월에 1.2 판이 나왔다.")
        XCTAssertEqual(NoiseCleaner.clean("(가 8:26). 그리고"), "(가 8:26). 그리고")
        XCTAssertEqual(NoiseCleaner.clean("모두 9년이나 걸렸다. 3 명이 왔다."), "모두 9년이나 걸렸다. 3 명이 왔다.")
        XCTAssertEqual(NoiseCleaner.clean("가운뎃점 하나·는 그대로"), "가운뎃점 하나·는 그대로")
    }

    func testQuoteContinuesOntoNextPageAsSingleLine() {
        let p1 = RawPage(index: 0, height: pageH, lines: [
            line("본문 첫 줄은 오른쪽 끝까지 이어지고", x: 0.05, to: 0.95, y: 0.100),
            line("여기서 끝납니다.", x: 0.05, to: 0.50, y: 0.136),
            line("인용한 글은 길게 이어지다가", x: 0.07, to: 0.95, y: 0.230),
            line("쪽이 바뀌는 곳에서도 여전히", x: 0.07, to: 0.95, y: 0.266),
        ], source: .ocr)
        let p2 = RawPage(index: 1, height: pageH, lines: [
            line("끝나지 않았습니다.", x: 0.07, to: 0.40, y: 0.100),
            line("다음 본문은 오른쪽 끝까지 이어지고", x: 0.05, to: 0.95, y: 0.190),
            line("한 줄 더 오른쪽 끝까지 이어지다가", x: 0.05, to: 0.95, y: 0.226),
            line("끝납니다.", x: 0.05, to: 0.30, y: 0.262),
        ], source: .ocr)
        let text = DocumentBuilder.build(pages: [p1, p2]).text
        XCTAssertTrue(text.contains("> 인용한 글은 길게 이어지다가 쪽이 바뀌는 곳에서도 여전히 끝나지 않았습니다."), text)
        guard let marker = text.range(of: "[p.2]"), let quoteEnd = text.range(of: "끝나지 않았습니다."),
              let body = text.range(of: "다음 본문은") else { return XCTFail(text) }
        XCTAssertTrue(quoteEnd.upperBound <= marker.lowerBound, text)
        XCTAssertTrue(marker.upperBound <= body.lowerBound, text)
    }

    func testLexiconDecidesSpacing() {
        let lexicon = Lexicon(rows: ["그는 결코 물러서지 않았다", "거기에 정죄함이 없다", "우리 공동체는 하나다"])
        XCTAssertTrue(lexicon.contains("결코"))
        XCTAssertFalse(lexicon.contains("그는"), "줄의 첫 낱말은 넣지 않는다")
        // 두 조각이 각각 낱말로 나오면 띄운다
        XCTAssertEqual(LineJoiner.join("이제는 결코", "정죄함이 없다", lexicon: lexicon), "이제는 결코 정죄함이 없다")
        // 붙인 꼴이 낱말로 나오면 붙인다
        XCTAssertEqual(LineJoiner.join("바로 우리 공동", "체는 하나다", lexicon: lexicon), "바로 우리 공동체는 하나다")
        // 한 글자 조각은 홀로 쓰는 말일 때만 띄운다
        let singles = Lexicon(rows: ["저기 가 보자 얼른", "함께 기를 쓰고 달렸다", "정말 더 좋은 날이다", "아주 중요한 일이다"])
        XCTAssertEqual(LineJoiner.join("집에 가", "기를 바랐다", lexicon: singles), "집에 가기를 바랐다")
        XCTAssertEqual(LineJoiner.join("이것이 더", "중요한 일이다", lexicon: singles), "이것이 더 중요한 일이다")
        // 근거가 없으면 이전 규칙대로
        XCTAssertEqual(LineJoiner.join("이제는 결코", "정죄함이 없다"), "이제는 결코정죄함이 없다")
        // 괄호 뒤의 조사
        XCTAssertEqual(LineJoiner.join("변화”(가 12:2)를", "받은 사람"), "변화”(가 12:2)를 받은 사람")
    }

    func testRunningFooterWithGluedPageNumberIsRemoved() {
        // 쪽번호가 제목에 붙어 읽힌 쪽("142여름…")과 따로 읽힌 쪽("144" + "여름…")이 섞여 있다.
        var pages: [RawPage] = []
        for i in 0..<4 {
            var lines = [
                line("본문 \(i) 첫째 줄은 끝까지 차 있고", x: 0.05, to: 0.95, y: 0.30),
                line("둘째 줄에서 끝납니다.", x: 0.05, to: 0.50, y: 0.336),
            ]
            switch i {
            case 0:
                lines.append(line("142여름 이야기 모음", x: 0.05, to: 0.40, y: 1.34))
            case 2:
                lines.append(line("144", x: 0.05, to: 0.08, y: 1.34))
                lines.append(line("여름 이야기 모음", x: 0.10, to: 0.40, y: 1.34))
            default:
                lines.append(line("작은 소제목 하나 \(142 + i)", x: 0.60, to: 0.95, y: 1.34))
            }
            pages.append(RawPage(index: i, height: pageH, lines: lines, source: .ocr))
        }
        let text = DocumentBuilder.build(pages: pages).text
        XCTAssertFalse(text.contains("이야기 모음"), text)
        XCTAssertFalse(text.contains("소제목 하나"), text)
        XCTAssertFalse(text.contains("144"), text)
        XCTAssertTrue(text.contains("본문 3 첫째 줄은"), text)
    }

    func testNarrowRunOfLinesIsStillOneParagraph() {
        // 그림 옆처럼 글 폭이 좁아진 구간: 오른쪽 끝이 서로 나란하면 짧은 줄이 아니다.
        let page = RawPage(index: 0, height: pageH, lines: [
            line("좁은 구간의 첫 줄이 여기까지 오고", x: 0.05, to: 0.60, y: 0.200),
            line("둘째 줄도 같은 자리에서 끝나며", x: 0.05, to: 0.60, y: 0.236),
            line("셋째 줄까지 폭이 좁다가 그다음에", x: 0.05, to: 0.60, y: 0.272),
            line("넓은 구간으로 돌아와 오른쪽 끝까지 이어지고", x: 0.05, to: 0.95, y: 0.308),
            line("한 줄 더 오른쪽 끝까지 이어진 뒤에", x: 0.05, to: 0.95, y: 0.344),
            line("끝납니다.", x: 0.05, to: 0.25, y: 0.380),
        ], source: .ocr)
        let text = DocumentBuilder.build(pages: [page], options: plain()).text
        XCTAssertFalse(text.trimmingCharacters(in: .newlines).contains("\n"), text)
        XCTAssertTrue(text.contains("좁은 구간의 첫 줄이"), text)
        XCTAssertTrue(text.hasSuffix("끝납니다.\n"), text)
    }

    func testEndsTerminal() {
        XCTAssertTrue(LineJoiner.endsTerminal("그렇게 말했습니다.7"))
        XCTAssertTrue(LineJoiner.endsTerminal("그렇지 않겠지요.”"))
        XCTAssertTrue(LineJoiner.endsTerminal("정말입니까?"))
        XCTAssertFalse(LineJoiner.endsTerminal("정말 대단히"))
        XCTAssertFalse(LineJoiner.endsTerminal("2012"))
    }

    func testEmptyInput() {
        let result = DocumentBuilder.build(pages: [
            RawPage(index: 0, height: pageH, lines: [], source: .ocr),
        ])
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.emptyPages, [1])
    }
}
