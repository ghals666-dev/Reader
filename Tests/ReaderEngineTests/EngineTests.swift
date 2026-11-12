import CoreGraphics
import CoreText
import Foundation
import XCTest
import ReaderCore
@testable import ReaderEngine

/// 실제 PDFKit·Vision을 거치는 통합 테스트. macOS에서만 돈다.
final class EngineTests: XCTestCase {
    struct Item {
        var text: String
        var x: CGFloat      // 왼쪽 끝. 음수면 가운데 정렬
        var top: CGFloat    // 위에서부터의 거리
    }

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
    static let keywords = ["사과나무", "고양이", "도서관", "기차역", "우체국", "박물관"]

    /// 595×842pt 쪽 기준의 배치. 줄마다 왼쪽·오른쪽을 번갈아 그린다.
    func items(pageNumber: Int) -> [Item] {
        var out = [Item(text: "제3장 테스트 문서", x: -1, top: 30)]
        for r in 0..<4 {
            let top = 150 + CGFloat(r) * 22
            out.append(Item(text: Self.left[r], x: 40, top: top))
            out.append(Item(text: Self.right[r], x: 320, top: top))
        }
        out.append(Item(text: "\(pageNumber)", x: -1, top: 815))
        return out
    }

    func draw(_ items: [Item], in ctx: CGContext, width: CGFloat, height: CGFloat, scale: CGFloat) {
        let font = CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, 13 * scale, nil)
        for item in items {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(gray: 0, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: item.text, attributes: attributes))
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x = item.x < 0 ? (width - lineWidth) / 2 : item.x * scale
            ctx.textPosition = CGPoint(x: x, y: height - item.top * scale - 13 * scale)
            CTLineDraw(line, ctx)
        }
    }

    func temporaryURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    /// 글자를 그림으로만 담은 PDF(텍스트 레이어 없음)
    func makeScannedPDF() throws -> URL {
        let url = temporaryURL("scanned.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        let scale: CGFloat = 3
        let w = Int(595 * scale), h = Int(842 * scale)
        for n in 0..<2 {
            let bitmap = try XCTUnwrap(CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: w, height: h))
            draw(items(pageNumber: 7 + n), in: bitmap, width: CGFloat(w), height: CGFloat(h), scale: scale)
            let image = try XCTUnwrap(bitmap.makeImage())
            pdf.beginPDFPage(nil)
            pdf.draw(image, in: box)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }

    /// 글자를 그대로 담은 PDF(텍스트 레이어 있음)
    func makeTextPDF() throws -> URL {
        let url = temporaryURL("text.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for n in 0..<2 {
            pdf.beginPDFPage(nil)
            draw(items(pageNumber: 7 + n), in: pdf, width: 595, height: 842, scale: 1)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }

    func assertReadingOrder(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let squeezed = text.filter { !$0.isWhitespace }
        var cursor = squeezed.startIndex
        for word in Self.keywords {
            guard let found = squeezed.range(of: word, range: cursor..<squeezed.endIndex) else {
                return XCTFail("'\(word)'의 순서가 어긋났거나 인식되지 않음:\n\(text)", file: file, line: line)
            }
            cursor = found.upperBound
        }
        XCTAssertFalse(squeezed.contains("테스트문서"), "머리글이 남음:\n\(text)", file: file, line: line)
        XCTAssertTrue(text.contains("[p."), "쪽 마커 없음:\n\(text)", file: file, line: line)
    }

    func testScannedTwoColumnPDFGoesThroughOCR() throws {
        let url = try makeScannedPDF()
        let pages = try XCTUnwrap(PDFTextExtractor().extract(url: url))
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages.allSatisfy { $0.source == .ocr })
        let text = DocumentBuilder.build(pages: pages).text
        print("--- OCR 결과 ---\n\(text)\n---------------")
        assertReadingOrder(text)
    }

    func testTextLayerPDFSkipsOCR() throws {
        let url = try makeTextPDF()
        let pages = try XCTUnwrap(PDFTextExtractor().extract(url: url))
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages.allSatisfy { $0.source == .textLayer })
        let text = DocumentBuilder.build(pages: pages).text
        print("--- 텍스트 레이어 결과 ---\n\(text)\n---------------")
        assertReadingOrder(text)
    }

    func testConverterWritesNextToPDFAndSkipsExisting() throws {
        let url = try makeTextPDF()
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
