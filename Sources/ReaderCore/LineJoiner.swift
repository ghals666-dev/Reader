import Foundation

/// 줄 끝에서 끊긴 두 줄을 한 문단으로 잇는다.
///
/// 한국어 책은 낱말 중간에서도 줄을 바꾸므로, 줄을 이을 때 띄어 쓸지 붙여 쓸지를
/// 좌표만으로는 알 수 없다. 그래서 조사·어미 목록을 이용한 어림 규칙을 쓴다.
/// 완벽하지 않지만(대략 열에 하나는 틀린다) 낱말을 온전히 살리는 쪽이
/// AI가 읽기에 더 낫다.
public enum LineJoiner {
    /// 다음 줄이 이 말로 시작하면 앞 낱말에 붙는 조사·어미로 본다.
    static let strongHeads: Set<String> = [
        "은", "는", "을", "를", "의", "에", "와", "과", "께", "게", "럼", "인",
        "에서", "에게", "에는", "에도", "에서는", "에게서", "으로", "으로는", "으로서", "으로써",
        "로서", "로써", "로는", "부터", "까지", "처럼", "보다", "마다", "조차", "마저", "밖에",
        "이나", "이라도", "라도", "이며", "이고", "이라고", "라고", "이라는", "라는", "이란",
        "이지만", "지만", "는데", "인데", "으며", "으면", "면서", "으면서", "므로", "으므로",
        "니다", "습니다", "입니다", "됩니다", "합니다", "습니까", "입니까",
        "이다", "였다", "이었다", "였습니다", "이었습니다",
        "하는", "하고", "하며", "하여", "해서", "했다", "했습니다", "한다", "하면", "하지",
        "하기", "하게", "하다", "해야", "했고", "했던", "하신",
        "되는", "되고", "되어", "되었다", "된다",
        "들", "들이", "들은", "들을", "들의", "들에게", "들과", "들도",
        "적", "적인", "적으로", "지는", "지요", "죠", "까요", "네요", "군요", "세요", "십시오",
        "이라", "이라면", "에요", "예요", "이에요", "만은", "만이",
    ]

    /// 홀로 낱말이 되기도 하는 한 글자 조사·어미. 닫는 따옴표 뒤에서만 쓴다.
    static let weakHeads: Set<String> = [
        "이", "가", "도", "만", "다", "나", "고", "요", "며", "란", "로", "서", "든", "야", "라", "지",
    ]

    /// 앞 줄 마지막 낱말이 이 글자로 끝나면 낱말이 끝난 것으로 본다.
    static let wordFinals: Set<Character> = Set("은는을를에의도로고며면서게히다요한할된던만와과지이가")

    static let openers: Set<Character> = Set("([{“‘「『《〈")
    static let closersBefore: Set<Character> = Set(".,!?:;)]}”’」』》〉%…")
    static let closingQuotes: Set<Character> = Set("”’\"')」』》〉]")

    public static func join(_ first: String, _ second: String) -> String {
        var a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }

        // 영문 하이픈 줄바꿈: "inter-" + "national"
        if a.last == "-", a.count >= 2, let head = b.first, isLowerLatin(head) {
            let before = a[a.index(a.endIndex, offsetBy: -2)]
            if isLowerLatin(before) {
                a.removeLast()
                return a + b
            }
        }
        return a + separator(a, b) + b
    }

    static func separator(_ a: String, _ b: String) -> String {
        guard let last = a.last, let first = b.first else { return "" }
        if openers.contains(last) { return "" }
        if closersBefore.contains(first) { return "" }

        let head = String(b.prefix(while: { isHangul($0) }))

        if isHangul(last) && isHangul(first) {
            if strongHeads.contains(head) { return "" }
            var tailCount = 0
            for ch in a.reversed() {
                if isHangul(ch) { tailCount += 1 } else { break }
            }
            if tailCount >= 2 && wordFinals.contains(last) { return " " }
            return ""
        }
        if isHangul(first) && closingQuotes.contains(last) {
            return (strongHeads.contains(head) || weakHeads.contains(head)) ? "" : " "
        }
        if isIdeograph(last) && (isIdeograph(first) || isHangul(first)) { return "" }
        if isHangul(last) && isIdeograph(first) { return "" }
        return " "
    }

    /// 문장이 끝나는 줄인지. 닫는 따옴표와 각주 번호는 건너뛰고 본다.
    public static func endsTerminal(_ text: String) -> Bool {
        var t = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var digits = 0
        let superscripts: Set<Character> = Set("⁰¹²³⁴⁵⁶⁷⁸⁹")
        while let c = t.last {
            if closingQuotes.contains(c) {
                t.removeLast()
            } else if superscripts.contains(c) || (c.isASCII && c.isNumber && digits < 3) {
                digits += 1
                t.removeLast()
            } else {
                break
            }
        }
        guard let c = t.last else { return false }
        return ".!?…。".contains(c)
    }

    static func isHangul(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0xAC00...0xD7A3).contains(v)
    }

    static func isIdeograph(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v) || (0x3040...0x30FF).contains(v)
    }

    static func isLowerLatin(_ c: Character) -> Bool {
        c.isASCII && c.isLetter && c.isLowercase
    }
}
