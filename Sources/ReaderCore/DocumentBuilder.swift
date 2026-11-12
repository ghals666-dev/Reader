import Foundation

/// 쪽별 원시 줄 → AI가 읽기 좋은 하나의 텍스트.
public enum DocumentBuilder {
    public static let lowConfidenceThreshold = 0.5

    public static func build(pages: [RawPage], options: BuildOptions = BuildOptions()) -> BuildResult {
        let clean = HeaderFooterFilter.clean(pages)
        let labels = pageLabels(clean)

        let layout = clean.map { (index: $0.index, segments: ColumnLayout.segments(for: $0.lines)) }
        let paragraphs = ParagraphBuilder.build(pages: layout, structure: options.structureMarkers)

        var chunks: [String] = []
        var currentPage: Int?
        var lastQuoteBlock: Int?

        for p in paragraphs {
            let text = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let body = chunks.joined(separator: "\n\n")
        return BuildResult(text: body.isEmpty ? "" : body + "\n",
                           pages: reports, lowConfidencePages: low, emptyPages: empty)
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
