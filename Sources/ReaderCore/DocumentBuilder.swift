import Foundation

/// 쪽별 원시 줄 → AI가 읽기 좋은 하나의 텍스트.
public enum DocumentBuilder {
    public static let lowConfidenceThreshold = 0.5

    public static func build(pages: [RawPage], options: BuildOptions = BuildOptions(),
                             title: String? = nil) -> BuildResult {
        let clean = HeaderFooterFilter.clean(pages)
        let labels = pageLabels(clean)

        let layout = clean.map { (index: $0.index, segments: ColumnLayout.segments(for: $0.lines)) }
        let lexicon = Lexicon(rows: layout.flatMap { $0.segments.flatMap { $0.rows.map { $0.text } } })
        let paragraphs = ParagraphBuilder.build(pages: layout, structure: options.structureMarkers,
                                                lexicon: lexicon)

        var chunks: [String] = []
        var currentPage: Int?
        var lastQuoteBlock: Int?

        for p in paragraphs {
            var text = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if options.cleanNoise { text = NoiseCleaner.clean(text) }
            guard !text.isEmpty else { continue }

            if options.pageMarkers, currentPage != p.pageIndex {
                currentPage = p.pageIndex
                chunks.append("[p.\(labels[p.pageIndex] ?? p.pageIndex + 1)]")
                lastQuoteBlock = nil
            }

            switch p.kind {
            case .heading:
                chunks.append(options.structureMarkers ? "## " + text : text)
                lastQuoteBlock = nil
            case .quote:
                let rendered: String
                if options.structureMarkers {
                    rendered = text.split(separator: "\n", omittingEmptySubsequences: true)
                        .map { "> " + $0 }.joined(separator: "\n")
                } else {
                    rendered = text
                }
                // 같은 인용 덩어리의 줄들은 빈 줄 없이 붙여 둔다.
                if lastQuoteBlock == p.blockID, !chunks.isEmpty {
                    chunks[chunks.count - 1] += "\n" + rendered
                } else {
                    chunks.append(rendered)
                }
                lastQuoteBlock = p.blockID
            case .body:
                chunks.append(text)
                lastQuoteBlock = nil
            }
        }

        let reports = clean.map { page in
            PageReport(index: page.index,
                       label: labels[page.index] ?? page.index + 1,
                       source: page.source,
                       lineCount: page.lines.count,
                       meanConfidence: page.meanConfidence)
        }
        let low = reports.filter {
            $0.source == .ocr && $0.lineCount > 0 && $0.meanConfidence < lowConfidenceThreshold
        }.map { $0.label }
        let empty = reports.filter { $0.lineCount == 0 }.map { $0.label }

        if options.header, let title, !chunks.isEmpty {
            chunks.insert(contentsOf: header(title: title, pageCount: pages.count, options: options), at: 0)
        }
        let body = chunks.joined(separator: "\n\n")
        return BuildResult(text: body.isEmpty ? "" : body + "\n",
                           pages: reports, lowConfidencePages: low, emptyPages: empty)
    }

    /// 글을 읽을 AI가 표시의 뜻을 바로 알 수 있도록 맨 위에 붙이는 안내.
    static func header(title: String, pageCount: Int, options: BuildOptions) -> [String] {
        var notes = ["이 글은 PDF에서 자동으로 옮긴 것입니다.", "전체 \(pageCount)쪽."]
        var marks: [String] = []
        if options.pageMarkers { marks.append("[p.N]은 원본의 쪽 번호") }
        if options.structureMarkers {
            marks.append("##는 소제목")
            marks.append(">는 인용문")
        }
        if !marks.isEmpty { notes.append(marks.joined(separator: ", ") + " 표시입니다.") }
        notes.append("글자 인식과 띄어쓰기에 오류가 조금 섞여 있을 수 있습니다.")
        return ["# " + title, "(" + notes.joined(separator: " ") + ")"]
    }

    /// 인쇄된 쪽번호가 PDF 순번과 일정한 차이로 이어지면 그 번호를 쓴다.
    static func pageLabels(_ pages: [CleanPage]) -> [Int: Int] {
        var votes: [Int: Int] = [:]
        var numbered = 0
        for page in pages {
            if let n = page.printedNumber {
                votes[n - page.index, default: 0] += 1
                numbered += 1
            }
        }
        var offset: Int?
        if let best = votes.max(by: { $0.value < $1.value }),
           Double(best.value) >= 0.6 * Double(numbered),
           best.value >= 2 || pages.count == 1 {
            offset = best.key
        }
        var labels: [Int: Int] = [:]
        for page in pages {
            if let off = offset, page.index + off > 0 {
                labels[page.index] = page.index + off
            } else {
                labels[page.index] = page.index + 1
            }
        }
        return labels
    }
}
