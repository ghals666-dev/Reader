import Foundation

/// 쪽 너비를 1로 둔 좌표계의 사각형. 원점은 왼쪽 위, y는 아래로 증가한다.
/// x와 y 모두 쪽 너비로 나눈 값이라 가로·세로 길이를 직접 비교할 수 있다.
public struct Rect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func union(_ other: Rect) -> Rect {
        let nx = min(minX, other.minX)
        let ny = min(minY, other.minY)
        return Rect(x: nx, y: ny,
                    width: max(maxX, other.maxX) - nx,
                    height: max(maxY, other.maxY) - ny)
    }
}

/// OCR 또는 텍스트 레이어에서 얻은 한 줄(또는 줄 조각).
public struct TextLine: Equatable, Sendable {
    public var text: String
    public var box: Rect
    public var confidence: Double

    public init(text: String, box: Rect, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

public enum PageSource: String, Sendable {
    case textLayer
    case ocr
}

/// 한 쪽에서 뽑은 원시 결과.
public struct RawPage: Sendable {
    /// 0부터 시작하는 PDF 쪽 순번
    public var index: Int
    /// 쪽 높이 ÷ 쪽 너비
    public var height: Double
    public var lines: [TextLine]
    public var source: PageSource

    public init(index: Int, height: Double, lines: [TextLine], source: PageSource) {
        self.index = index
        self.height = height
        self.lines = lines
        self.source = source
    }
}

public struct BuildOptions: Sendable {
    /// `[p.N]` 쪽 마커를 넣는다.
    public var pageMarkers = true
    /// 소제목(`## `)과 인용문(`> `) 표시를 넣는다.
    public var structureMarkers = true

    /// 본문에 섞인 각주 번호와 깨진 말줄임표 같은 인식 잡음을 지운다.
    public var cleanNoise = true

    public init(pageMarkers: Bool = true, structureMarkers: Bool = true, cleanNoise: Bool = true) {
        self.pageMarkers = pageMarkers
        self.structureMarkers = structureMarkers
        self.cleanNoise = cleanNoise
    }
}

public struct PageReport: Sendable {
    public var index: Int
    /// 쪽 마커에 쓰는 번호 (인쇄된 쪽번호를 찾으면 그 번호, 아니면 PDF 순번)
    public var label: Int
    public var source: PageSource
    public var lineCount: Int
    public var meanConfidence: Double
}

public struct BuildResult: Sendable {
    public var text: String
    public var pages: [PageReport]
    /// 인식 신뢰도가 낮은 쪽의 번호(label)
    public var lowConfidencePages: [Int]
    /// 글자가 하나도 없는 쪽의 번호(label)
    public var emptyPages: [Int]
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    return s[s.count / 2]
}

func lowerQuartile(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    return s[s.count / 4]
}
