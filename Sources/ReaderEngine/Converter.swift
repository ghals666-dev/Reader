import Foundation
import ReaderCore

public struct ConversionOptions: Sendable {
    public var build = BuildOptions()
    /// 텍스트 레이어가 있어도 무조건 OCR한다.
    public var forceOCR = false
    /// 이미 txt가 있어도 다시 만든다.
    public var overwrite = false

    public init() {}
}

public struct ConversionSummary: Sendable {
    public var outputURL: URL
    public var pageCount: Int
    public var ocrPages: Int
    public var textLayerPages: Int
    public var characters: Int
    public var lowConfidencePages: [Int]
    public var emptyPages: [Int]
}

public enum ConversionOutcome: Sendable {
    case converted(ConversionSummary)
    case skipped(URL)
    case cancelled
    case failed(String)
}

public enum Converter {
    /// 원본 PDF 옆의 같은 이름 txt
    public static func outputURL(for pdf: URL) -> URL {
        pdf.deletingPathExtension().appendingPathExtension("txt")
    }

    public static func convert(pdf: URL,
                               options: ConversionOptions = ConversionOptions(),
                               progress: (Double) -> Void = { _ in },
                               isCancelled: () -> Bool = { false }) -> ConversionOutcome {
        let output = outputURL(for: pdf)
        if !options.overwrite, FileManager.default.fileExists(atPath: output.path) {
            return .skipped(output)
        }
        do {
            let extractor = PDFTextExtractor(forceOCR: options.forceOCR)
            guard let pages = try extractor.extract(url: pdf, progress: progress,
                                                    isCancelled: isCancelled) else {
                return .cancelled
            }
            let result = DocumentBuilder.build(pages: pages, options: options.build)
            try result.text.write(to: output, atomically: true, encoding: .utf8)
            return .converted(ConversionSummary(
                outputURL: output,
                pageCount: pages.count,
                ocrPages: pages.filter { $0.source == .ocr }.count,
                textLayerPages: pages.filter { $0.source == .textLayer }.count,
                characters: result.text.count,
                lowConfidencePages: result.lowConfidencePages,
                emptyPages: result.emptyPages))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 파일과 폴더가 섞인 목록에서 PDF만 골라 펼친다(폴더는 하위까지).
    public static func expand(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL) {
            guard url.pathExtension.lowercased() == "pdf" else { return }
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted { out.append(url) }
        }
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                var found: [URL] = []
                if let walker = fm.enumerator(at: url, includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles]) {
                    for case let file as URL in walker { found.append(file) }
                }
                found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                found.forEach(add)
            } else {
                add(url)
            }
        }
        return out
    }
}
