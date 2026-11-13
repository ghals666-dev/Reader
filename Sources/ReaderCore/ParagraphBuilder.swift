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
    /// 덩어리 전체가 단의 왼쪽 끝보다 들여 짜여 있는지
    var blockInset = false
    var blockRowCount = 1
}

/// 줄을 문단으로 묶는다. 보수적으로 동작한다:
/// 이어도 된다는 근거가 분명할 때만 줄을 잇고, 애매하면 줄바꿈을 그대로 둔다.
enum ParagraphBuilder {
    static let blockGapFactor = 1.4
    static let indentMin = 0.45
    static let indentMax = 6.0
    static let shortBy = 2.0

    static func build(pages: [(index: Int, segments: [Segment])], structure: Bool,
                      lexicon: Lexicon? = nil) -> [Paragraph] {
        var out: [Paragraph] = []
        var nextBlockID = 0

        for page in pages {
            let allRows = page.segments.flatMap { $0.rows }
            guard let bodyH = median(allRows.map { $0.box.height }), bodyH > 0 else { continue }

            for segment in page.segments {
                let paragraphs = build(segment: segment, pageIndex: page.index, bodyH: bodyH,
                                       structure: structure, lexicon: lexicon,
                                       nextBlockID: &nextBlockID)
                for (i, p) in paragraphs.enumerated() {
                    if i == 0, let prev = out.last, continues(prev, p) {
                        out[out.count - 1].text = LineJoiner.join(prev.text, p.text, lexicon: lexicon)
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
        guard prev.kind != .heading, next.kind != .heading else { return false }
        // 문장이 끝난 채로 넘어갔다면 새 문단일 수 있으므로 잇지 않는다.
        guard prev.lastRowFull, !LineJoiner.endsTerminal(prev.text) else { return false }
        if prev.kind == next.kind { return !next.startsIndented }
        // 인용문의 마지막 한 줄만 다음 쪽으로 넘어온 경우: 한 줄뿐이라 인용문으로
        // 분류되지 못했지만, 들여 짜여 있고 앞 인용문이 끝나지 않았으므로 이어 붙인다.
        return prev.kind == .quote && next.kind == .body && next.blockInset && next.blockRowCount == 1
    }

    private static func build(segment: Segment, pageIndex: Int, bodyH: Double,
                              structure: Bool, lexicon: Lexicon?,
                              nextBlockID: inout Int) -> [Paragraph] {
        let rows = segment.rows
        guard !rows.isEmpty else { return [] }
        let colL = rows.map { $0.box.minX }.min() ?? 0
        let colR = rows.map { $0.box.maxX }.max() ?? 0
        let colW = colR - colL

        // 줄 간격이 벌어진 곳에서 덩어리를 나눈다.
        // 쪽 안에 줄 간격이 다른 구역(글상자, 인용문)이 섞여 있을 수 있으므로,
        // 쪽 전체가 아니라 앞뒤 두 줄씩의 간격과 견준다. 빈 줄만큼 크게 벌어진 곳은 무조건 나눈다.
        var pitches: [Double] = []
        for i in 1..<max(rows.count, 1) {
            pitches.append(rows[i].box.minY - rows[i - 1].box.minY)
        }
        let blankLine = bodyH * 2.4
        func isGap(_ k: Int) -> Bool {
            let pitch = pitches[k]
            if pitch > blankLine { return true }
            var near: [Double] = []
            for j in [k - 2, k - 1, k + 1, k + 2] where j >= 0 && j < pitches.count {
                if pitches[j] >= 0.5 * bodyH { near.append(pitches[j]) }
            }
            guard !near.isEmpty else { return false }
            near.sort()
            return pitch > near[(near.count - 1) / 2] * blockGapFactor
        }

        var blocks: [[Row]] = [[rows[0]]]
        for i in 1..<max(rows.count, 1) {
            if isGap(i - 1) {
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
            let blockInset = inset > indentMin * bodyH
            let isQuote = blockInset
                && rows.count > block.count
                && (block.count >= 2 || blockH < 0.9 * bodyH)
            let kind: ParagraphKind = isQuote ? .quote : .body
            let refL = isQuote ? bL : colL

            // 오른쪽 끝이 가지런한 줄이 둘 이상이면 그 끝을, 아니면 단의 끝을 기준으로 삼는다.
            let reachingRight = block.filter { bR - $0.box.maxX < bodyH }.count
            let refR = (block.count >= 3 && reachingRight >= 2) ? bR : colR

            /// 문단 첫 줄처럼 들여 쓴 줄인지.
            /// 스캔이 조금 기울면 줄의 왼쪽 끝이 아래로 갈수록 밀리므로, 바로 앞뒤 줄과 견준다.
            func indented(_ i: Int) -> Bool {
                var reference = refL
                var near: [Double] = []
                for j in [i - 1, i + 1] where j >= 0 && j < block.count {
                    near.append(block[j].box.minX)
                }
                if let nearest = near.min() { reference = nearest }
                let d = block[i].box.minX - reference
                return d > indentMin * bodyH && d < indentMax * bodyH
            }

            /// 문단의 마지막 줄처럼 오른쪽이 비어 있는 줄인지.
            /// 이웃 줄과 오른쪽 끝이 나란하면 글 폭이 좁아진 구간일 뿐이므로 짧은 줄로 보지 않는다.
            func short(_ i: Int) -> Bool {
                let row = block[i]
                guard refR - row.box.maxX > shortBy * bodyH else { return false }
                for j in [i - 1, i + 1] where j >= 0 && j < block.count {
                    if abs(block[j].box.maxX - row.box.maxX) < 0.7 * bodyH { return false }
                }
                return true
            }

            var text = block[0].text
            var startIndented = indented(0)
            for i in 1..<max(block.count, 1) {
                let prev = block[i - 1]
                let row = block[i]
                let prevShort = short(i - 1)
                if indented(i) || (prevShort && LineJoiner.endsTerminal(prev.text)) {
                    out.append(Paragraph(kind: kind, text: text, pageIndex: pageIndex,
                                         blockID: blockID, startsIndented: startIndented,
                                         lastRowFull: !prevShort,
                                         blockInset: blockInset, blockRowCount: block.count))
                    text = row.text
                    startIndented = indented(i)
                } else if prevShort {
                    // 짧게 끝났지만 문장이 끝나지 않았다: 목록·시 등일 수 있으니 줄바꿈 유지
                    text += "\n" + row.text
                } else {
                    text = LineJoiner.join(text, row.text, lexicon: lexicon)
                }
            }
            out.append(Paragraph(kind: kind, text: text, pageIndex: pageIndex,
                                 blockID: blockID, startsIndented: startIndented,
                                 lastRowFull: !short(block.count - 1),
                                 blockInset: blockInset, blockRowCount: block.count))
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
