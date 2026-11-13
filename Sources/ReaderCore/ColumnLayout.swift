import Foundation

/// 같은 높이의 조각을 합친, 화면에 보이는 한 줄.
struct Row {
    var text: String
    var box: Rect
    var confidence: Double
}

/// 한 단(또는 단을 가로지르는 띠) 안에서 읽는 순서대로 놓인 줄 묶음.
struct Segment {
    var rows: [Row]
    var spanning: Bool
}

/// 1단/2단을 판별하고 읽는 순서를 정한다.
///
/// 2단 판별은 "가운데 부근에 거의 어떤 줄도 지나가지 않는 세로 띠(gutter)가 있고,
/// 그 양쪽에 줄이 3개 이상씩 나란히 있다"로 단순하게 잡는다.
/// 확신이 없으면 1단으로 처리한다.
enum ColumnLayout {
    static let edgeSlack = 0.004

    static func segments(for lines: [TextLine]) -> [Segment] {
        guard !lines.isEmpty else { return [] }
        guard let g = findGutter(lines) else {
            return [Segment(rows: mergeRows(lines), spanning: false)]
        }
        let sorted = lines.sorted { $0.box.midY < $1.box.midY }
        var out: [Segment] = []
        var left: [TextLine] = []
        var right: [TextLine] = []
        var span: [TextLine] = []

        func flushColumns() {
            if !left.isEmpty { out.append(Segment(rows: mergeRows(left), spanning: false)) }
            if !right.isEmpty { out.append(Segment(rows: mergeRows(right), spanning: false)) }
            left.removeAll()
            right.removeAll()
        }
        func flushSpan() {
            if !span.isEmpty { out.append(Segment(rows: mergeRows(span), spanning: true)) }
            span.removeAll()
        }

        for line in sorted {
            if isSpanning(line, gutter: g) {
                flushColumns()
                span.append(line)
            } else {
                flushSpan()
                if line.box.midX < g { left.append(line) } else { right.append(line) }
            }
        }
        flushColumns()
        flushSpan()
        return out
    }

    static func isSpanning(_ line: TextLine, gutter g: Double) -> Bool {
        line.box.minX < g - edgeSlack && line.box.maxX > g + edgeSlack
    }

    /// 단 사이 여백의 x좌표. 2단이 아니면 nil.
    static func findGutter(_ lines: [TextLine]) -> Double? {
        let n = lines.count
        guard n >= 6 else { return nil }
        let minX = lines.map { $0.box.minX }.min() ?? 0
        let maxX = lines.map { $0.box.maxX }.max() ?? 0
        let width = maxX - minX
        guard width > 0.3 else { return nil }

        let tolerance = Int(Double(n) * 0.15)
        let steps = 200
        var best: (start: Double, end: Double)?
        var runStart: Double?
        var runEnd = 0.0

        func closeRun() {
            if let s = runStart {
                if best == nil || runEnd - s > best!.end - best!.start {
                    best = (s, runEnd)
                }
            }
            runStart = nil
        }

        for step in 0...steps {
            let x = minX + width * (0.25 + 0.5 * Double(step) / Double(steps))
            let crossing = lines.filter {
                $0.box.minX < x - edgeSlack && $0.box.maxX > x + edgeSlack
            }.count
            if crossing <= tolerance {
                if runStart == nil { runStart = x }
                runEnd = x
            } else {
                closeRun()
            }
        }
        closeRun()

        guard let run = best, run.end - run.start >= 0.012 else { return nil }
        // 오른쪽 단은 왼쪽 가장자리가 가지런하므로 띠의 오른쪽 끝 가까이를 경계로 삼는다.
        let g = run.end - min(0.006, (run.end - run.start) / 2)

        var leftLines: [TextLine] = []
        var rightLines: [TextLine] = []
        var spanning = 0
        for line in lines {
            if isSpanning(line, gutter: g) {
                spanning += 1
            } else if line.box.midX < g {
                leftLines.append(line)
            } else {
                rightLines.append(line)
            }
        }
        guard leftLines.count >= 3, rightLines.count >= 3 else { return nil }
        guard Double(spanning) <= 0.3 * Double(n) else { return nil }

        // 두 단이 실제로 나란히 놓여 있는지(세로 범위가 겹치는지) 확인
        let lTop = leftLines.map { $0.box.minY }.min() ?? 0
        let lBottom = leftLines.map { $0.box.maxY }.max() ?? 0
        let rTop = rightLines.map { $0.box.minY }.min() ?? 0
        let rBottom = rightLines.map { $0.box.maxY }.max() ?? 0
        let overlap = min(lBottom, rBottom) - max(lTop, rTop)
        let shorter = min(lBottom - lTop, rBottom - rTop)
        guard shorter > 0, overlap >= 0.5 * shorter else { return nil }
        return g
    }

    /// 같은 높이에 놓인 조각들을 왼쪽부터 이어 한 줄로 만든다.
    static func mergeRows(_ lines: [TextLine]) -> [Row] {
        let sorted = lines.sorted { $0.box.midY < $1.box.midY }
        var groups: [(box: Rect, parts: [TextLine])] = []
        for line in sorted {
            if let last = groups.last {
                let overlap = min(last.box.maxY, line.box.maxY) - max(last.box.minY, line.box.minY)
                let smaller = min(last.box.height, line.box.height)
                if smaller > 0, overlap > 0.5 * smaller {
                    groups[groups.count - 1].box = last.box.union(line.box)
                    groups[groups.count - 1].parts.append(line)
                    continue
                }
            }
            groups.append((line.box, [line]))
        }
        let rows: [Row] = groups.compactMap { group in
            let parts = group.parts.sorted { $0.box.minX < $1.box.minX }
            let text = parts.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !text.isEmpty else { return nil }
            let conf = parts.map { $0.confidence }.reduce(0, +) / Double(parts.count)
            return Row(text: text, box: group.box, confidence: conf)
        }
        return rows.sorted { $0.box.minY < $1.box.minY }
    }
}
