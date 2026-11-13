import Foundation

/// 문서 안에서 줄 중간에 온전한 모습으로 나온 낱말(어절) 모음.
///
/// 줄 끝에서 끊긴 두 조각을 붙일지 띄울지 정할 때 근거로 쓴다.
/// 붙인 꼴("공동체는")이 책 어딘가에 한 낱말로 나오면 붙이고,
/// 두 조각("결코", "정죄함이")이 각각 따로 나오면 띄운다.
public struct Lexicon: Sendable {
    private var words: Set<String> = []

    public init(rows: [String]) {
        for row in rows {
            let tokens = row.split(whereSeparator: { $0.isWhitespace })
            // 줄의 첫 낱말과 끝 낱말은 잘린 조각일 수 있으므로 뺀다.
            guard tokens.count >= 3 else { continue }
            for token in tokens[1..<(tokens.count - 1)] {
                if let word = Lexicon.hangulCore(token) { words.insert(word) }
            }
        }
    }

    public func contains(_ word: String) -> Bool {
        words.contains(word)
    }

    public var isEmpty: Bool { words.isEmpty }

    /// 앞뒤 문장부호를 떼어 낸 뒤 한글로만 이루어져 있으면 그 낱말을 돌려준다.
    static func hangulCore(_ token: Substring) -> String? {
        var core = token
        while let first = core.first, !LineJoiner.isHangul(first) { core.removeFirst() }
        while let last = core.last, !LineJoiner.isHangul(last) { core.removeLast() }
        guard !core.isEmpty, core.allSatisfy({ LineJoiner.isHangul($0) }) else { return nil }
        return String(core)
    }
}
