import Foundation
import ReaderCore
import ReaderEngine

let usage = """
사용법: reader-cli [옵션] <PDF 또는 폴더>...

  --no-page-markers   [p.N] 쪽 마커를 넣지 않는다
  --plain             소제목(##)·인용문(>) 표시를 넣지 않는다
  --force-ocr         텍스트 레이어가 있어도 OCR한다
  --overwrite         이미 txt가 있어도 다시 만든다
  --stdout            파일로 저장하지 않고 화면에 출력한다
"""

var options = ConversionOptions()
var toStdout = false
var inputs: [URL] = []

for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "--no-page-markers": options.build.pageMarkers = false
    case "--plain": options.build.structureMarkers = false
    case "--force-ocr": options.forceOCR = true
    case "--overwrite": options.overwrite = true
    case "--stdout": toStdout = true
    case "-h", "--help":
        print(usage)
        exit(0)
    default: inputs.append(URL(fileURLWithPath: arg))
    }
}

let pdfs = Converter.expand(inputs)
guard !pdfs.isEmpty else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

func report(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

var failures = 0
for pdf in pdfs {
    if toStdout {
        do {
            let pages = try PDFTextExtractor(forceOCR: options.forceOCR).extract(url: pdf) ?? []
            let result = DocumentBuilder.build(pages: pages, options: options.build)
            print(result.text, terminator: "")
            let ocr = pages.filter { $0.source == .ocr }.count
            report("\(pdf.lastPathComponent): \(pages.count)쪽 (OCR \(ocr)쪽)")
        } catch {
            failures += 1
            report("\(pdf.lastPathComponent): 실패 - \(error.localizedDescription)")
        }
        continue
    }
    switch Converter.convert(pdf: pdf, options: options) {
    case .converted(let s):
        var note = "\(pdf.lastPathComponent): \(s.pageCount)쪽 → \(s.outputURL.lastPathComponent) (OCR \(s.ocrPages)쪽)"
        if !s.lowConfidencePages.isEmpty {
            note += " | 인식이 불확실한 쪽: \(s.lowConfidencePages.map(String.init).joined(separator: ", "))"
        }
        if !s.emptyPages.isEmpty {
            note += " | 빈 쪽: \(s.emptyPages.map(String.init).joined(separator: ", "))"
        }
        report(note)
    case .skipped(let url):
        report("\(pdf.lastPathComponent): 건너뜀 (\(url.lastPathComponent) 이미 있음)")
    case .cancelled:
        report("\(pdf.lastPathComponent): 취소됨")
    case .failed(let message):
        failures += 1
        report("\(pdf.lastPathComponent): 실패 - \(message)")
    }
}
exit(failures == 0 ? 0 : 1)
