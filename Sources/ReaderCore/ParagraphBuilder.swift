import Foundation

enum ParagraphKind {
    case body
    case heading
    case quote
}

struct Paragraph {
    var kind: ParagraphKind
    var text: String
    /// 이 문단이 시작된 쪽 (0부터)
    var pageIndex: Int
    /// 같은 덩어리(빈 줄로 구분된 블록)에서 나온 문단은 번호가 같다.
    var blockID: Int
    var startsIndented: Bool
    /// 마지막 줄이 단의 오른쪽 끝까지 차 있는지 (다음 단·쪽으로 이어질 수 있는지)
    var lastRowFull: Bool
}

/// 줄을 문단으로 묶는다. 보수적으로 동작한다:
/// 이어도 된다는 근거가 분명할 때만 줄을 잇고, 애매하면 줄바꿈을 그대로 둔다.
enum ParagraphBuilder {
    static let blockGapFactor = 1.4
    static let indentMin = 0.45
    static let indentMax = 6.0
    static let shortBy = 2.0

    static func build(pages: [(index: Int, segments: [Segment])], structure: Bool) -> [Paragraph] {
        var out: [Paragraph] = []
        var nextBlockID = 0

        for page in pages {
            let allRows = page.segments.flatMap { $0.rows }
            guard let bodyH = median(allRows.map { $0.box.height }), bodyH > 0 else { continue }

            for segment in page.segments {
                let paragraphs = build(segment: segment, pageIndex: page.index, bodyH: bodyH,
                                       structure: structure, nextBlockID: &nextBlockID)
                for (i, p) in paragraphs.enumerated() {
                    if i == 0, let prev = out.last, continues(prev, p) {
                        out[out.count - 1].text = LineJoiner.join(prev.text, p.text)
                        out[out.count - 1].lastRowFull = p.lastRowFull
                    } else {
                        out.append(p)
                    }
                }
            }
        }
        return out
    }

    /// 앞 단·앞 쪽의 마지막 문단이 다음 단·쪽의 첫 문단으로 이어지는지.
    static func continues(_ prev: Paragraph, _ next: Paragraph) -> Bool {
        guard prev.kind == next.kind, prev.kind != .heading else { return false }
        guard prev.lastRowFull, !next.startsIndented else { return false }
        // 문장이 끝난 채로 넘어갔다면 새 문단일 수 있으므로 잇지 않는다.
        return !LineJoiner.endsTerminal(prev.text)
    }

    private static func build(segment: Segment, pageIndex: Int, bodyH: Double,
                              structure: Bool, nextBlockID: inout Int) -> [Paragraph] {
        let rows = segment.rows
        guard !rows.isEmpty else { return [] }
        let colL = rows.map { $0.box.minX }.min() ?? 0
        let colR = rows.map { $0.box.maxX }.max() ?? 0
        let colW = colR - colL

        // 줄 간격이 평소보다 눈에 띄게 벌어진 곳에서 덩어리를 나눈다.
        var pitches: [Double] = []
        for i in 1..<max(rows.count, 1) {
            pitches.append(rows[i].box.minY - rows[i - 1].box.minY)
        }
        let positive = pitches.filter { $0 > 0 }
        let threshold: Double
        if positive.count >= 3, let base = lowerQuartile(positive) {
            threshold = base * blockGapFactor
        } else {
            threshold = bodyH * 2.2
        }

        var blocks: [[Row]] = [[rows[0]]]
        for i in 1..<max(rows.count, 1) {
            if pitches[i - 1] > threshold {
                blocks.append([rows[i]])
            } else {
                blocks[blocks.count - 1].append(rows[i])
            }
        }

        var out: [Paragraph] = []
        for block in blocks {
            let blockID = nextBlockID
            nextBlockID += 1
            let bL = block.map { $0.box.minX }.min() ?? colL
            let bR = block.map { $0.box.maxX }.max() ?? colR
            let blockH = median(block.map { $0.box.height }) ?? bodyH

            if isHeading(block, colL: colL, colR: colR, colW: colW, segmentRows: rows.count) {
                let text = block.map { $0.text }.joined(separator: " ")
                out.append(Paragraph(kind: .heading, text: text, pageIndex: pageIndex,
                                     blockID: blockID, startsIndented: true, lastRowFull: false))
                continue
            }

            let inset = bL - colL
            let isQuote = inset > indentMin * bodyH
                && rows.count > block.count
                && (block.count >= 2 || blockH < 0.9 * bodyH)
            let kind: ParagraphKind = isQuote ? .quote : .body
            let refL = isQuote ? bL : colL

            // 오른쪽 끝이 가지런한 줄이 둘 이상이면 그 끝을, 아니면 단의 끝을 기준으로 삼는다.
            let reachingRight = block.filter { bR - $0.box.maxX < bodyH }.count
            let refR = (block.count >= 3 && reachingRight >= 2) ? bR : colR

            func indented(_ row: Row) -> Bool {
                let d = row.box.minX - refL
                return d > indentMin * bodyH && d < indentMax * bodyH
            }
            func short(_ row: Row) -> Bool {
                refR - row.box.maxX > shortBy * bodyH
            }

            var text = block[0].text
            var startIndented = indented(block[0])
            for i in 1..<max(block.count, 1) {
                let prev = block[i - 1]
                let row = block[i]
                let prevShort = short(prev)
                if indented(row) || (prevShort && LineJoiner.endsTerminal(prev.text)) {
                    out.append(Paragraph(kind: kind, text: text, pageIndex: pageIndex,
                                         blockID: blockID, startsIndented: startIndented,
                                         lastRowFull: !prevShort))
                    text = row.text
                    startIndented = indented(row)
                } else if prevShort {
                    // 짧게 끝났지만 문장이 끝나지 않았다: 목록·시 등일 수 있으니 줄바꿈 유지
                    text += "\n" + row.text
                } else {
                    text = LineJoiner.join(text, row.text)
                }
            }
            out.append(Paragraph(kind: kind, text: text, pageIndex: pageIndex,
                                 blockID: blockID, startsIndented: startIndented,
                                 lastRowFull: !short(block[block.count - 1])))
        }
        return out
    }

    /// 가운데 정렬된 한두 줄짜리 짧은 덩어리를 소제목으로 본다.
    private static func isHeading(_ block: [Row], colL: Double, colR: Double,
                                  colW: Double, segmentRows: Int) -> Bool {
        guard block.count <= 2, segmentRows >= 4, colW > 0 else { return false }
        for row in block {
            let lm = row.box.minX - colL
            let rm = colR - row.box.maxX
            guard lm > 0.12 * colW, rm > 0.12 * colW, abs(lm - rm) < 0.1 * colW else { return false }
            guard row.text.count <= 50 else { return false }
        }
        guard let last = block.last else { return false }
        return !LineJoiner.endsTerminal(last.text)
    }
}
