import AppKit
import SwiftUI

// MARK: - 도구 위치 찾기

enum Tools {
    static let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    static func find(_ name: String) -> String? {
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent(name).path) }
        candidates += searchDirs.map { "\($0)/\(name)" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - 다운로드 상태

enum Mode: String, CaseIterable, Identifiable {
    case video = "영상 (mp4)"
    case audio = "음원만 (mp3)"
    var id: String { rawValue }
}

@MainActor
final class Downloader: ObservableObject {
    @Published var urlText = ""
    @Published var mode: Mode = .video
    @Published var folder: URL = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @Published var progress: Double = 0
    @Published var running = false
    @Published var log = ""
    @Published var status = "주소를 붙여 넣고 다운로드를 누르세요."

    let ytdlp = Tools.find("yt-dlp")
    let ffmpeg = Tools.find("ffmpeg")
    private var process: Process?

    var canStart: Bool {
        !running && ytdlp != nil && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { folder = url }
    }

    func start() {
        guard let ytdlp else { return }
        let urls = urlText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !urls.isEmpty else { return }

        var args = ["--newline", "--no-playlist", "--restrict-filenames",
                    "-P", folder.path, "-o", "%(title).150B [%(id)s].%(ext)s"]
        if let ffmpeg { args += ["--ffmpeg-location", ffmpeg] }
        switch mode {
        case .video:
            if ffmpeg != nil {
                args += ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]
            } else {
                args += ["-f", "b[ext=mp4]/b"]
            }
        case .audio:
            guard ffmpeg != nil else {
                status = "mp3 변환에는 ffmpeg가 필요합니다. 터미널에서 brew install ffmpeg"
                return
            }
            args += ["-x", "--audio-format", "mp3"]
        }
        args += urls

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ytdlp)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (Tools.searchDirs + [env["PATH"] ?? ""]).joined(separator: ":")
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.consume(text) }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let code = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor in self?.finished(code: code, cancelled: reason == .uncaughtSignal) }
        }

        log = ""
        progress = 0
        status = "다운로드 중…"
        running = true
        do {
            try p.run()
            process = p
        } catch {
            running = false
            status = "실행하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func cancel() { process?.terminate() }

    func revealFolder() { NSWorkspace.shared.open(folder) }

    private func consume(_ text: String) {
        log += text
        if log.count > 20000 { log = String(log.suffix(15000)) }
        // "[download]  42.3% of ..." 에서 퍼센트를 읽는다.
        if let range = text.range(of: #"\[download\]\s+([0-9.]+)%"#, options: .regularExpression) {
            let digits = text[range].filter { "0123456789.".contains($0) }
            if let v = Double(digits) { progress = v / 100 }
        }
    }

    private func finished(code: Int32, cancelled: Bool) {
        running = false
        process = nil
        if cancelled {
            status = "취소했습니다."
        } else if code == 0 {
            progress = 1
            status = "완료! \(folder.lastPathComponent) 폴더에 저장했습니다."
        } else {
            status = "실패했습니다. 아래 로그를 확인하세요. (코드 \(code))"
        }
    }
}

// MARK: - 화면

struct ContentView: View {
    @StateObject private var dl = Downloader()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("동영상 주소 (여러 개는 줄바꿈으로 구분)").font(.headline)
            TextEditor(text: $dl.urlText)
                .font(.body.monospaced())
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Picker("형식", selection: $dl.mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                Spacer()
                Text(dl.folder.path).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("폴더 선택…") { dl.chooseFolder() }
            }

            HStack {
                Button(dl.running ? "다운로드 중…" : "다운로드") { dl.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!dl.canStart)
                if dl.running { Button("취소") { dl.cancel() } }
                Button("폴더 열기") { dl.revealFolder() }
                Spacer()
            }

            ProgressView(value: dl.progress)
            Text(dl.status).font(.callout)
            if dl.ytdlp == nil {
                Text("yt-dlp를 찾을 수 없습니다. 터미널에서 brew install yt-dlp")
                    .foregroundStyle(.red).font(.callout)
            } else if dl.ffmpeg == nil {
                Text("ffmpeg가 없어 mp3 변환과 고화질 합치기는 꺼져 있습니다. (brew install ffmpeg)")
                    .foregroundStyle(.secondary).font(.caption)
            }

            ScrollView {
                Text(dl.log).font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 460)
    }
}

@main
struct VideoGrabberApp: App {
    var body: some Scene {
        WindowGroup("VideoGrabber") {
            ContentView()
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}
