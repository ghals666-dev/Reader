import Foundation

/// 머리글·바닥글·쪽번호를 걷어낸 쪽.
struct CleanPage {
    var index: Int
    var height: Double
    var lines: [TextLine]
    var printedNumber: Int?
    var source: PageSource
    var meanConfidence: Double
}

/// 쪽 위·아래 가장자리에서 반복되는 글과 쪽번호를 제거한다.
///
/// 본문을 지우는 사고를 막기 위해 조건을 좁게 잡는다.
/// - 쪽 위·아래 10% 구역 안에 있는 줄만 후보로 본다.
/// - 쪽번호 모양(`12`, `- 12 -`, `126 / 179`)이거나,
///   앞뒤 두 쪽 안에서 같은 높이에 거의 같은 글이 다시 나올 때만 지운다.
enum HeaderFooterFilter {
    static let zoneRatio = 0.10
    static let neighbourReach = 2

    private struct Candidate {
        var lineIndex: Int
        var top: Bool
        var relY: Double
        var key: String
        var number: Int?
        var x: Double
    }

    static func clean(_ pages: [RawPage]) -> [CleanPage] {
        let candidates: [[Candidate]] = pages.map { page in
            guard page.height > 0 else { return [] }
            var out: [Candidate] = []
            for (i, line) in page.lines.enumerated() {
                let rel = line.box.midY / page.height
                let top = rel < zoneRatio
                let bottom = rel > 1 - zoneRatio
                guard top || bottom else { continue }
                out.append(Candidate(lineIndex: i, top: top, relY: rel,
                                     key: key(line.text),
                                     number: pageNumber(in: line.text),
                                     x: line.box.minX))
            }
            return out
        }

        var result: [CleanPage] = []
        for (p, page) in pages.enumerated() {
            var remove = Set<Int>()
            for c in candidates[p] {
                if c.number != nil {
                    remove.insert(c.lineIndex)
                    continue
                }
                let lo = max(0, p - neighbourReach)
                let hi = min(pages.count - 1, p + neighbourReach)
                var repeated = false
                for q in lo...hi where q != p && !repeated {
                    repeated = candidates[q].contains { other in
                        other.top == c.top
                            && abs(other.relY - c.relY) < 0.02
                            && similar(other.key, c.key)
                    }
                }
                if repeated { remove.insert(c.lineIndex) }
            }

            let numbered = candidates[p].filter { $0.number != nil }
            let bottomFirst = numbered.filter { !$0.top }.sorted { $0.x < $1.x }
            let topFirst = numbered.filter { $0.top }.sorted { $0.x < $1.x }
            let printed = (bottomFirst.first ?? topFirst.first)?.number

            let kept = page.lines.enumerated().filter { !remove.contains($0.offset) }.map { $0.element }
            let conf = kept.isEmpty ? 1 : kept.map { $0.confidence }.reduce(0, +) / Double(kept.count)
            result.append(CleanPage(index: page.index, height: page.height, lines: kept,
                                    printedNumber: printed, source: page.source,
                                    meanConfidence: conf))
        }
        return result
    }

    /// 비교용 열쇠: 공백을 없애고 숫자는 `#`으로 바꾼다.
    static func key(_ text: String) -> String {
        var out = ""
        for ch in text.lowercased() where !ch.isWhitespace {
            out.append(ch.isNumber ? "#" : ch)
        }
        return out
    }

    /// 줄 전체가 쪽번호 모양이면 그 번호를 돌려준다.
    static func pageNumber(in text: String) -> Int? {
        let ignored: Set<Character> = ["-", "–", "—", "·", "•", "|", "[", "]", "(", ")"]
        let t = String(text.filter { !$0.isWhitespace && !ignored.contains($0) })
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2, let first = parts.first else { return nil }
        func digits(_ s: Substring) -> Bool {
            s.count <= 4 && s.allSatisfy { $0.isASCII && $0.isNumber }
        }
        guard !first.isEmpty, digits(first) else { return nil }
        if parts.count == 2, !digits(parts[1]) { return nil }
        return Int(first)
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return !a.isEmpty }
        guard a.count >= 4, b.count >= 4 else { return false }
        let limit = max(1, min(a.count, b.count) / 5)
        if abs(a.count - b.count) > limit { return false }
        return editDistance(Array(a), Array(b)) <= limit
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
