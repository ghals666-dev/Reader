import Foundation

/// 인식 과정에서 본문에 섞여 든 잡음을 지운다. 뜻이 바뀔 수 있는 것은 건드리지 않는다.
public enum NoiseCleaner {
    static let dots: Set<Character> = Set("·•∙⋅")
    static let sentenceEnd: Set<Character> = Set(".!?")
    static let closingQuotes: Set<Character> = Set("”’\"'」』")

    public static func clean(_ text: String) -> String {
        stripFootnoteMarks(fixEllipsis(text))
    }

    /// 가운뎃점·불릿이 둘 이상 이어지면 말줄임표를 잘못 읽은 것이다.
    static func fixEllipsis(_ text: String) -> String {
        var out = ""
        var run = ""
        func flush() {
            if run.count >= 2 { out += "…" } else { out += run }
            run = ""
        }
        for ch in text {
            if dots.contains(ch) { run.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }

    /// 문장 끝이나 닫는 따옴표에 바로 붙은 1~3자리 숫자는 각주 번호다("했습니다.3").
    /// "1.2"나 "2012년"처럼 숫자가 내용인 경우는 건드리지 않는다.
    static func stripFootnoteMarks(_ text: String) -> String {
        let chars = Array(text)
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            guard ch.isASCII, ch.isNumber, let before = out.last else {
                out.append(ch)
                i += 1
                continue
            }
            var j = i
            while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
            let after: Character? = j < chars.count ? chars[j] : nil
            let length = j - i

            var isMark = false
            if length <= 3 {
                if closingQuotes.contains(before) {
                    // 따옴표 뒤: 띄어쓰기·끝·한글("것”4이라고")이 이어질 때
                    isMark = after == nil || after!.isWhitespace || LineJoiner.isHangul(after!)
                } else if sentenceEnd.contains(before), out.count >= 2 {
                    let prior = out[out.count - 2]
                    let afterOK = after == nil || after!.isWhitespace
                    isMark = afterOK && (LineJoiner.isHangul(prior) || closingQuotes.contains(prior) || prior == ")")
                }
            }
            if !isMark { out.append(contentsOf: chars[i..<j]) }
            i = j
        }
        return String(out)
    }
}
