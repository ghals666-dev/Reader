import CoreGraphics
import CoreText
import Foundation
import XCTest
import ReaderCore
@testable import ReaderEngine

/// 실제 PDFKit·Vision을 거치는 통합 테스트. macOS에서만 돈다.
/// 시험용 문장은 모두 이 테스트를 위해 지어낸 것이다.
final class EngineTests: XCTestCase {
    struct Item {
        var text: String
        var x: CGFloat          // 왼쪽 끝(pt). 음수면 가운데 정렬
        var top: CGFloat        // 위에서부터의 거리(pt)
        var size: CGFloat = 13  // 글자 크기(pt)
    }

    static let pageW: CGFloat = 595
    static let pageH: CGFloat = 842

    // MARK: - PDF 만들기

    func font(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, size, nil)
    }

    func ctLine(_ text: String, size: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(ctLine(text, size: size), nil, nil, nil))
    }

    func draw(_ items: [Item], in ctx: CGContext, scale: CGFloat) {
        for item in items {
            let size = item.size * scale
            let line = ctLine(item.text, size: size)
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x = item.x < 0 ? (Self.pageW * scale - lineWidth) / 2 : item.x * scale
            ctx.textPosition = CGPoint(x: x, y: Self.pageH * scale - item.top * scale - size)
            CTLineDraw(line, ctx)
        }
    }

    /// scanned가 참이면 글자를 그림으로만 담고(텍스트 레이어 없음), 거짓이면 글자를 그대로 담는다.
    func makePDF(_ pages: [[Item]], scanned: Bool, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)

        var box = CGRect(x: 0, y: 0, width: Self.pageW, height: Self.pageH)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for items in pages {
            pdf.beginPDFPage(nil)
            if scanned {
                let scale: CGFloat = 3
                let w = Int(Self.pageW * scale), h = Int(Self.pageH * scale)
                let bitmap = try XCTUnwrap(CGContext(
                    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
                bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
                bitmap.fill(CGRect(x: 0, y: 0, width: w, height: h))
                draw(items, in: bitmap, scale: scale)
                pdf.draw(try XCTUnwrap(bitmap.makeImage()), in: box)
            } else {
                draw(items, in: pdf, scale: 1)
            }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }

    func squeeze(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }

    func dump(_ pages: [RawPage]) {
        for page in pages {
            print("-- \(page.index + 1)쪽 원시 줄 (\(page.source.rawValue))")
            for line in page.lines {
                let b = line.box
                print(String(format: "  x %.3f~%.3f y %.3f h %.3f | ", b.minX, b.maxX, b.minY, b.height) + line.text)
            }
        }
    }

    // MARK: - 2단 문서

    static let left = [
        "우리 마을에는 사과나무가 많이 있고",
        "고양이 한 마리가 그 아래에서 자며",
        "도서관 옆에는 작은 공원이 있어서",
        "아이들이 날마다 모여 뛰어놉니다.",
    ]
    static let right = [
        "기차역 앞에는 오래된 시계가 있고",
        "우체국 직원은 언제나 친절하며",
        "박물관에는 옛날 물건이 가득해서",
        "사람들이 주말마다 찾아옵니다.",
    ]

    /// 줄마다 왼쪽·오른쪽을 번갈아 그린다.
    func twoColumnPage(number: Int) -> [Item] {
        var out = [Item(text: "제3장 테스트 문서", x: -1, top: 30)]
        for r in 0..<4 {
            let top = 150 + CGFloat(r) * 22
            out.append(Item(text: Self.left[r], x: 40, top: top))
            out.append(Item(text: Self.right[r], x: 320, top: top))
        }
        out.append(Item(text: "\(number)", x: -1, top: 815))
        return out
    }

    /// 왼쪽 단 네 줄이 모두 나온 뒤에 오른쪽 단 네 줄이 나와야 한다.
    func assertColumnOrder(_ text: String, exact: Bool,
                           file: StaticString = #filePath, line: UInt = #line) {
        let squeezed = squeeze(text)
        // OCR은 한두 글자 틀릴 수 있으므로 줄마다 핵심 낱말만 본다.
        let expected = exact
            ? (Self.left + Self.right).map(squeeze)
            : ["사과나무", "고양이", "도서관", "아이들", "기차역", "우체국", "박물관", "사람들"]
        var cursor = squeezed.startIndex
        for piece in expected {
            guard let found = squeezed.range(of: piece, range: cursor..<squeezed.endIndex) else {
                return XCTFail("'\(piece)'의 순서가 어긋났거나 빠짐:\n\(text)", file: file, line: line)
            }
            cursor = found.upperBound
        }
        XCTAssertFalse(squeezed.contains("테스트문서"), "머리글이 남음:\n\(text)", file: file, line: line)
    }

    func testScannedTwoColumnPDFGoesThroughOCR() throws {
        let url = try makePDF([twoColumnPage(number: 7), twoColumnPage(number: 8)],
                              scanned: true, name: "scanned.pdf")
        let pages = try XCTUnwrap(PDFTextExtractor().extract(url: url))
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages.allSatisfy { $0.source == .ocr })
        let text = DocumentBuilder.build(pages: pages).text
        print("--- 2단 OCR 결과 ---\n\(text)---------------")
        assertColumnOrder(text, exact: false)
        XCTAssertEqual(text.components(separatedBy: "[p.").count - 1, 2, "쪽 마커가 둘이어야 함:\n\(text)")
    }

    func testTextLayerTwoColumnPDFSkipsOCR() throws {
        let url = try makePDF([twoColumnPage(number: 7), twoColumnPage(number: 8)],
                              scanned: false, name: "text.pdf")
        let pages = try XCTUnwrap(PDFTextExtractor().extract(url: url))
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages.allSatisfy { $0.source == .textLayer })
        dump(pages)
        let text = DocumentBuilder.build(pages: pages).text
        print("--- 2단 텍스트 레이어 결과 ---\n\(text)---------------")
        // 텍스트 레이어는 글자가 정확하므로 한 글자도 빠지거나 섞이면 안 된다.
        assertColumnOrder(text, exact: true)
        XCTAssertTrue(text.contains("[p.7]"), text)
        XCTAssertTrue(text.contains("[p.8]"), text)
        XCTAssertFalse(text.contains("[p.9]"), text)
    }

    // MARK: - 책 모양 문서 (1단, 들여쓰기 문단, 소제목, 인용문, 쪽을 넘는 문단)

    static let paragraphs = [
        "봄이 오면 우리 동네 뒷산에는 진달래가 먼저 피어납니다. 아침마다 산책을 나서는 어르신들은 꽃이 핀 자리를 서로 알려 주며 인사를 나눕니다. 아이들은 학교 가는 길에 꽃잎을 주워 책갈피에 끼워 두곤 합니다. 그렇게 모은 꽃잎은 한 해가 지나도 색이 조금밖에 바래지 않습니다.",
        "여름에는 개울가에 모여 발을 담그는 사람이 많습니다. 물이 맑아서 작은 물고기가 발가락 사이로 지나가는 모습이 훤히 보입니다. 해가 기울 무렵이면 누군가 수박을 들고 나타나고, 모두가 둘러앉아 한 조각씩 나누어 먹습니다.",
        "가을이 되면 마을 전체가 바빠집니다. 논에서는 벼를 베고 밭에서는 고구마를 캡니다. 일손이 모자란 집에는 이웃들이 먼저 찾아가 돕습니다. 마을 이장님은 해마다 이맘때 같은 말씀을 하십니다.",
        "겨울에는 눈이 많이 내려 길이 자주 막힙니다. 그래도 사람들은 걱정하지 않습니다. 가을에 함께 쌓아 둔 장작과 곡식이 넉넉하기 때문입니다. 긴 밤에는 사랑방에 모여 옛이야기를 나누며 봄을 기다립니다. 눈이 그친 아침이면 집집마다 나와 골목의 눈을 함께 치웁니다.",
        "이듬해 봄, 진달래는 어김없이 다시 핍니다. 그리고 마을의 한 해도 처음부터 다시 시작됩니다.",
    ]
    static let heading = "가을걷이와 겨울 준비"
    static let quote = "혼자 하면 사흘 걸릴 일도 여럿이 하면 반나절이면 끝납니다. 품을 나누는 것이 곧 겨울을 나는 힘입니다. 올해도 서로의 밭을 제 밭처럼 돌보아 주시기 바랍니다."

    /// 한국어 책처럼 글자 단위로 줄을 바꾼다(낱말 중간에서도 끊긴다).
    func wrap(_ text: String, size: CGFloat, firstWidth: CGFloat, width: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""
        for ch in text {
            if current.isEmpty && ch == " " { continue }
            let limit = lines.isEmpty ? firstWidth : width
            if textWidth(current + String(ch), size: size) > limit {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = ch == " " ? "" : String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { lines.append(current.trimmingCharacters(in: .whitespaces)) }
        return lines
    }

    struct BookLayout {
        var pages: [[Item]]
        /// 1쪽의 마지막 줄 (다음 쪽으로 이어지는 문단의 중간)
        var lastLineOfFirstPage: String
    }

    func bookLayout() -> BookLayout {
        let left: CGFloat = 40, width: CGFloat = 515, indent: CGFloat = 13
        var page1: [Item] = []
        var page2: [Item] = []
        var top: CGFloat = 150
        var lastLine = ""

        func body(_ text: String, indented: Bool, into page: inout [Item]) -> [String] {
            let lines = wrap(text, size: 13, firstWidth: indented ? width - indent : width, width: width)
            for (i, line) in lines.enumerated() {
                page.append(Item(text: line, x: left + (i == 0 && indented ? indent : 0), top: top))
                top += 22
            }
            return lines
        }

        _ = body(Self.paragraphs[0], indented: false, into: &page1)
        _ = body(Self.paragraphs[1], indented: true, into: &page1)
        top += 22
        page1.append(Item(text: Self.heading, x: -1, top: top))
        top += 44
        _ = body(Self.paragraphs[2], indented: false, into: &page1)
        top += 14
        for line in wrap(Self.quote, size: 11, firstWidth: width - indent, width: width - indent) {
            page1.append(Item(text: line, x: left + indent, top: top, size: 11))
            top += 20
        }
        top += 14

        // 넷째 문단은 1쪽에서 두 줄만 쓰고 2쪽으로 넘긴다.
        let fourth = wrap(Self.paragraphs[3], size: 13, firstWidth: width - indent, width: width)
        let keep = min(2, fourth.count - 1)
        for (i, line) in fourth.enumerated() {
            if i == keep { top = 80 }
            let item = Item(text: line, x: left + (i == 0 ? indent : 0), top: top)
            if i < keep { page1.append(item); lastLine = line } else { page2.append(item) }
            top += 22
        }
        _ = body(Self.paragraphs[4], indented: true, into: &page2)

        for (n, _) in [page1, page2].enumerated() {
            let extras = [
                Item(text: "제2장 마을의 사계절", x: -1, top: 30, size: 11),
                Item(text: "\(126 + n) / 179", x: -1, top: 815, size: 11),
            ]
            if n == 0 { page1 += extras } else { page2 += extras }
        }
        return BookLayout(pages: [page1, page2], lastLineOfFirstPage: lastLine)
    }

    func checkBook(_ text: String, layout: BookLayout, exact: Bool,
                   file: StaticString = #filePath, line: UInt = #line) {
        let chunks = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let headings = chunks.filter { $0.hasPrefix("## ") }
        let quotes = chunks.filter { $0.hasPrefix("> ") }
        let markers = chunks.filter { $0.hasPrefix("[p.") }
        let bodies = chunks.filter { !$0.hasPrefix("## ") && !$0.hasPrefix("> ") && !$0.hasPrefix("[p.") }

        XCTAssertEqual(headings.count, 1, "소제목은 하나:\n\(text)", file: file, line: line)
        XCTAssertEqual(quotes.count, 1, "인용문 덩어리는 하나:\n\(text)", file: file, line: line)
        XCTAssertEqual(markers, ["[p.126]", "[p.127]"], "쪽 마커:\n\(text)", file: file, line: line)
        // 쪽을 넘는 문단은 하나로 이어져야 한다. 다만 1쪽 마지막 줄이 우연히 문장 끝이면
        // 일부러 잇지 않으므로 문단이 하나 늘어난다.
        let expected = LineJoiner.endsTerminal(layout.lastLineOfFirstPage) ? 6 : 5
        XCTAssertEqual(bodies.count, expected, "본문 문단 수:\n\(text)", file: file, line: line)
        XCTAssertFalse(squeeze(text).contains("마을의사계절"), "머리글이 남음:\n\(text)", file: file, line: line)

        if exact {
            XCTAssertEqual(headings.first, "## " + Self.heading, file: file, line: line)
            // 줄을 이을 때 띄어쓰기는 어림이므로 공백을 빼고 비교한다.
            // 쪽을 넘는 문단 사이에는 쪽 마커가 낄 수 있으므로 마커도 빼고 본다.
            let squeezed = squeeze(chunks.filter { !$0.hasPrefix("[p.") }.joined())
                .replacingOccurrences(of: ">", with: "")
            for paragraph in Self.paragraphs + [Self.quote] {
                XCTAssertTrue(squeezed.contains(squeeze(paragraph)),
                              "문단이 온전하지 않음: \(paragraph.prefix(12))…\n\(text)", file: file, line: line)
            }
        }
    }

    func testScannedBookPageStructure() throws {
        let layout = bookLayout()
        let url = try makePDF(layout.pages, scanned: true, name: "book-scanned.pdf")
        let pages = try XCTUnwrap(PDFTextExtractor().extract(url: url))
        XCTAssertTrue(pages.allSatisfy { $0.source == .ocr })
        dump(pages)
        let text = DocumentBuilder.build(pages: pages).text
        print("--- 책 모양 OCR 결과 ---\n\(text)---------------")
        checkBook(text, layout: layout, exact: false)
    }

    func testTextLayerBookPageStructure() throws {
        let layout = bookLayout()
        let url = try makePDF(layout.pages, scanned: false, name: "book-text.pdf")
        let pages = try XCTUnwrap(PDFTextExtractor().extract(url: url))
        XCTAssertTrue(pages.allSatisfy { $0.source == .textLayer })
        let text = DocumentBuilder.build(pages: pages).text
        print("--- 책 모양 텍스트 레이어 결과 ---\n\(text)---------------")
        checkBook(text, layout: layout, exact: true)
    }

    // MARK: - 저장

    func testConverterWritesNextToPDFAndSkipsExisting() throws {
        let url = try makePDF([twoColumnPage(number: 7)], scanned: false, name: "text.pdf")
        guard case .converted(let summary) = Converter.convert(pdf: url) else {
            return XCTFail("변환 실패")
        }
        XCTAssertEqual(summary.outputURL.lastPathComponent, "text.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.outputURL.path))
        guard case .skipped = Converter.convert(pdf: url) else {
            return XCTFail("이미 있는 txt를 건너뛰지 않음")
        }
        var again = ConversionOptions()
        again.overwrite = true
        guard case .converted = Converter.convert(pdf: url, options: again) else {
            return XCTFail("덮어쓰기 실패")
        }
    }
}
