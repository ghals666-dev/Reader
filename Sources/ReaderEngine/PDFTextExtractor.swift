import AppKit
import Foundation
import PDFKit
import ReaderCore
import Vision

public enum ExtractError: Error, LocalizedError {
    case cannotOpen
    case locked
    case renderFailed(page: Int)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen: return "PDF를 열 수 없습니다."
        case .locked: return "암호가 걸린 PDF입니다."
        case .renderFailed(let page): return "\(page)쪽을 이미지로 그리지 못했습니다."
        }
    }
}

/// PDF의 각 쪽에서 줄 단위 텍스트와 좌표를 뽑는다.
/// 텍스트 레이어가 있으면 그대로 쓰고, 없으면 Apple Vision으로 OCR한다.
public struct PDFTextExtractor: Sendable {
    public var forceOCR = false
    public var languages = ["ko-KR", "en-US"]
    /// OCR용 렌더링 해상도
    public var dpi: Double = 300
    /// 렌더링 이미지의 긴 변 상한(픽셀)
    public var maxLongSide: Double = 4200

    public init(forceOCR: Bool = false) {
        self.forceOCR = forceOCR
    }

    public struct Extraction: Sendable {
        public var pages: [RawPage]
        /// 텍스트 레이어가 있었지만 품질이 낮아 OCR로 다시 읽었는지
        public var textLayerRejected: Bool
    }

    /// 취소되면 nil을 돌려준다.
    public func extract(url: URL,
                        progress: (Double) -> Void = { _ in },
                        isCancelled: () -> Bool = { false }) throws -> [RawPage]? {
        try extractDetailed(url: url, progress: progress, isCancelled: isCancelled)?.pages
    }

    /// 취소되면 nil을 돌려준다.
    public func extractDetailed(url: URL,
                                progress: (Double) -> Void = { _ in },
                                isCancelled: () -> Bool = { false }) throws -> Extraction? {
        guard let document = PDFDocument(url: url) else { throw ExtractError.cannotOpen }
        if document.isLocked { throw ExtractError.locked }

        var useTextLayer = !forceOCR
        var rejected = false
        if useTextLayer, textLayerLooksBad(document) {
            useTextLayer = false
            rejected = true
        }

        var pages: [RawPage] = []
        let count = document.pageCount
        for i in 0..<count {
            if isCancelled() { return nil }
            let page: RawPage? = try autoreleasepool {
                guard let pdfPage = document.page(at: i) else { return nil }
                return try extract(page: pdfPage, index: i, useTextLayer: useTextLayer)
            }
            if let page { pages.append(page) }
            progress(Double(i + 1) / Double(max(count, 1)))
        }
        return Extraction(pages: pages, textLayerRejected: rejected)
    }

    static func pageSize(_ page: PDFPage) -> (width: Double, height: Double) {
        let media = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        return (Double(rotated ? media.height : media.width), Double(rotated ? media.width : media.height))
    }

    func extract(page: PDFPage, index: Int, useTextLayer: Bool) throws -> RawPage {
        let (w, h) = Self.pageSize(page)
        let aspect = w > 0 ? h / w : 1.4

        if useTextLayer, let lines = textLayerLines(page: page) {
            return RawPage(index: index, height: aspect, lines: lines, source: .textLayer)
        }
        let lines = try ocrLines(page: page, index: index, width: w, height: h)
        return RawPage(index: index, height: aspect, lines: lines, source: .ocr)
    }

    // MARK: - 텍스트 레이어 품질 확인

    /// 스캔본에 다른 프로그램이 입혀 둔 텍스트 레이어는 글자가 많이 틀려 있을 수 있다.
    /// 글이 충분한 쪽을 최대 세 쪽 골라 Vision으로도 읽어 보고, 서로 크게 다르면 믿지 않는다.
    func textLayerLooksBad(_ document: PDFDocument) -> Bool {
        var candidates: [Int] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), page.rotation == 0, let string = page.string else { continue }
            if Self.signature(string).count >= 200 { candidates.append(i) }
        }
        guard !candidates.isEmpty else { return false }
        var picks: [Int] = []
        for quarter in 1...3 {
            let index = candidates[min(candidates.count - 1, candidates.count * quarter / 4)]
            if !picks.contains(index) { picks.append(index) }
        }

        var bad = 0
        for index in picks {
            let low: Bool = autoreleasepool {
                guard let page = document.page(at: index), let string = page.string else { return false }
                let (w, h) = Self.pageSize(page)
                guard let lines = try? ocrLines(page: page, index: index, width: w, height: h) else { return false }
                let seen = Self.signature(lines.map { $0.text }.joined(separator: " "))
                guard seen.count >= 50 else { return false }
                return Self.agreement(of: Self.signature(string), with: seen) < 0.7
            }
            if low { bad += 1 }
        }
        return bad * 2 > picks.count
    }

    /// 비교용으로 한글과 영문·숫자만 남긴 글자열
    static func signature(_ text: String) -> [Character] {
        text.lowercased().filter { ch in
            guard let v = ch.unicodeScalars.first?.value else { return false }
            return (0xAC00...0xD7A3).contains(v) || (ch.isASCII && (ch.isLetter || ch.isNumber))
        }
    }

    /// layer의 두 글자 묶음 가운데 seen에도 나오는 비율 (0~1)
    static func agreement(of layer: [Character], with seen: [Character]) -> Double {
        guard layer.count >= 2 else { return 1 }
        var counts: [String: Int] = [:]
        if seen.count >= 2 {
            for i in 0..<(seen.count - 1) { counts[String(seen[i...i + 1]), default: 0] += 1 }
        }
        var hits = 0
        for i in 0..<(layer.count - 1) {
            let key = String(layer[i...i + 1])
            if let n = counts[key], n > 0 {
                hits += 1
                counts[key] = n - 1
            }
        }
        return Double(hits) / Double(layer.count - 1)
    }

    // MARK: - 텍스트 레이어

    /// 쓸 만한 텍스트 레이어가 있으면 줄 조각으로 나눠 돌려준다.
    /// 글자 사이가 크게 벌어진 곳(단 사이 여백)에서는 줄을 쪼갠다.
    func textLayerLines(page: PDFPage) -> [TextLine]? {
        guard page.rotation == 0, let string = page.string else { return nil }
        let scalars = string.unicodeScalars
        let meaningful = scalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard meaningful.count >= 16 else { return nil }
        // 깨진 텍스트 레이어는 믿지 않는다.
        let broken = meaningful.filter { $0.value == 0xFFFD || (0xE000...0xF8FF).contains($0.value) }
        if Double(broken.count) > 0.1 * Double(meaningful.count) { return nil }

        let media = page.bounds(for: .mediaBox)
        guard media.width > 0 else { return nil }
        let pageW = Double(media.width)

        // 낱말마다 선택 영역을 만들어 글자와 좌표를 함께 얻는다.
        // (page.string의 순번과 characterBounds(at:)의 순번은 서로 어긋날 수 있어 쓰지 않는다.)
        let ns = string as NSString
        var lines: [TextLine] = []
        var words: [String] = []
        var box: CGRect?
        var lastBox: CGRect?

        func flush() {
            let text = words.joined(separator: " ")
            if !text.isEmpty, let b = box {
                let rect = Rect(x: Double(b.minX - media.minX) / pageW,
                                y: Double(media.maxY - b.maxY) / pageW,
                                width: Double(b.width) / pageW,
                                height: Double(b.height) / pageW)
                lines.append(TextLine(text: text, box: rect, confidence: 1))
            }
            words = []
            box = nil
            lastBox = nil
        }

        var tokenStart: Int?
        func endToken(at end: Int) {
            guard let start = tokenStart else { return }
            tokenStart = nil
            let range = NSRange(location: start, length: end - start)
            let word = ns.substring(with: range)
            guard let b = page.selection(for: range)?.bounds(for: page),
                  b.width > 0, b.height > 0 else {
                // 좌표를 알 수 없는 낱말은 지금 줄에 붙여 둔다.
                if box != nil { words.append(word) }
                return
            }
            if let lb = lastBox {
                let tall = max(lb.height, b.height)
                let overlap = min(lb.maxY, b.maxY) - max(lb.minY, b.minY)
                let sameRow = overlap > 0.5 * min(lb.height, b.height)
                // 다른 줄이거나, 단 사이 여백만큼 벌어졌거나, 왼쪽으로 되돌아갔으면 끊는다.
                if !sameRow || b.minX - lb.maxX > 2.5 * tall || b.minX < lb.maxX - tall {
                    flush()
                }
            }
            words.append(word)
            box = box.map { $0.union(b) } ?? b
            lastBox = b
        }

        let whitespace = CharacterSet.whitespacesAndNewlines
        for i in 0..<ns.length {
            let unit = ns.character(at: i)
            let isSpace = Unicode.Scalar(unit).map { whitespace.contains($0) } ?? false
            if isSpace {
                endToken(at: i)
                if unit == 10 || unit == 13 { flush() }
            } else if tokenStart == nil {
                tokenStart = i
            }
        }
        endToken(at: ns.length)
        flush()
        return lines.isEmpty ? nil : lines
    }

    // MARK: - OCR

    func ocrLines(page: PDFPage, index: Int, width: Double, height: Double) throws -> [TextLine] {
        guard width > 0, height > 0 else { return [] }
        let scale = min(dpi / 72.0, maxLongSide / max(width, height))
        let size = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExtractError.renderFailed(page: index + 1)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])

        let aspect = Double(cg.height) / Double(max(cg.width, 1))
        var lines: [TextLine] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let bb = observation.boundingBox  // 0~1, 원점은 왼쪽 아래
            let rect = Rect(x: Double(bb.minX),
                            y: Double(1 - bb.maxY) * aspect,
                            width: Double(bb.width),
                            height: Double(bb.height) * aspect)
            lines.append(TextLine(text: text, box: rect, confidence: Double(candidate.confidence)))
        }
        return lines
    }
}
