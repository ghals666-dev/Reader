import AppKit
import SwiftUI
import UserNotifications

// MARK: - 도구 위치 찾기

enum Tools {
    /// 앱 안에서 갱신한 yt-dlp를 넣어 두는 곳. 있으면 번들 것보다 먼저 쓴다.
    static var updatedYtdlp: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoGrabber/yt-dlp")
    }

    static let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    static func find(_ name: String) -> String? {
        var candidates: [String] = []
        if name == "yt-dlp" { candidates.append(updatedYtdlp.path) }
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent(name).path) }
        candidates += searchDirs.map { "\($0)/\(name)" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchDirs + [env["PATH"] ?? ""]).joined(separator: ":")
        return env
    }
}

// MARK: - 화질 선택지

struct Quality: Identifiable, Hashable {
    let height: Int?          // nil이면 최고 화질
    var id: Int { height ?? 0 }
    var label: String { height.map { "\($0)p" } ?? "최고 화질" }
}

enum CookieSource: String, CaseIterable, Identifiable {
    case off = "사용 안 함", safari = "safari", chrome = "chrome", firefox = "firefox", edge = "edge"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "로그인 쿠키 사용 안 함"
        case .safari: return "Safari 쿠키"
        case .chrome: return "Chrome 쿠키"
        case .firefox: return "Firefox 쿠키"
        case .edge: return "Edge 쿠키"
        }
    }
    var args: [String] { self == .off ? [] : ["--cookies-from-browser", rawValue] }
}

// MARK: - 다운로드 상태

@MainActor
final class Downloader: ObservableObject {
    enum Phase { case idle, fetching, ready, downloading }

    @Published var urlText = ""
    @Published var phase: Phase = .idle
    @Published var title = ""
    @Published var qualities: [Quality] = [Quality(height: nil)]
    @Published var quality = Quality(height: nil)
    @Published var folder: URL = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @Published var progress: Double = 0
    @Published var status = "영상 주소를 복사한 뒤 이 창을 여세요."
    @Published var ytdlpVersion = ""
    @Published var updating = false
    @Published var cookies: CookieSource = CookieSource(
        rawValue: UserDefaults.standard.string(forKey: "cookies") ?? "") ?? .off {
        didSet { UserDefaults.standard.set(cookies.rawValue, forKey: "cookies") }
    }

    @Published var ytdlp = Tools.find("yt-dlp")
    let ffmpeg = Tools.find("ffmpeg")
    private var process: Process?
    private var errorLines: [String] = []

    init() {
        refreshVersion()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    // MARK: yt-dlp 버전·갱신

    func refreshVersion() {
        guard let path = ytdlp else { ytdlpVersion = ""; return }
        Task {
            let v = await Task.detached { () -> String in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = ["--version"]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { return "" }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }.value
            ytdlpVersion = v
        }
    }

    func updateYtdlp() {
        guard !updating, phase != .downloading else { return }
        updating = true
        status = "yt-dlp 최신 버전을 받는 중…"
        Task {
            defer { updating = false }
            do {
                let src = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
                let (tmp, resp) = try await URLSession.shared.download(from: src)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let dest = Tools.updatedYtdlp
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
                ytdlp = dest.path
                refreshVersion()
                status = "yt-dlp를 최신 버전으로 갱신했습니다."
            } catch {
                status = "갱신하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: 클립보드

    /// 창이 열릴 때 호출. 클립보드가 http(s) 주소이고 지금 입력과 다르면 채우고 조회한다.
    func pasteFromClipboard() {
        guard phase == .idle || phase == .ready else { return }
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              text != urlText else { return }
        urlText = text
        fetchInfo()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { folder = url }
    }

    // MARK: 화질 조회

    func fetchInfo() {
        guard let ytdlp, phase != .downloading else { return }
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        phase = .fetching
        status = "영상 정보를 가져오는 중…"
        title = ""
        qualities = [Quality(height: nil)]
        quality = qualities[0]

        Task {
            let result = await Self.runInfo(ytdlp: ytdlp, url: url, cookies: cookies)
            guard urlText.trimmingCharacters(in: .whitespacesAndNewlines) == url else { return }
            if let (name, heights) = result {
                title = name
                qualities = [Quality(height: nil)] + heights.map { Quality(height: $0) }
                quality = qualities[0]
                phase = .ready
                status = heights.isEmpty ? "화질 정보가 없어 최고 화질로 받습니다." : "화질을 고르고 다운로드를 누르세요."
            } else {
                phase = .idle
                status = "이 주소에서 영상을 찾지 못했습니다."
            }
        }
    }

    private nonisolated static func runInfo(ytdlp: String, url: String, cookies: CookieSource) async -> (String, [Int])? {
        await Task.detached { () -> (String, [Int])? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ytdlp)
            p.arguments = ["-J", "--no-playlist", "--no-warnings"] + cookies.args + [url]
            p.environment = Tools.environment
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let name = (json["title"] as? String) ?? url
            let formats = (json["formats"] as? [[String: Any]]) ?? []
            let heights = Set(formats.compactMap { f -> Int? in
                guard (f["vcodec"] as? String) != "none", let h = f["height"] as? Int else { return nil }
                return h
            })
            return (name, heights.sorted(by: >))
        }.value
    }

    // MARK: 다운로드

    func start() {
        guard let ytdlp, phase == .ready || phase == .idle else { return }
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        var args = ["--newline", "--no-playlist", "--restrict-filenames",
                    "-P", folder.path, "-o", "%(title).150B [%(id)s].%(ext)s"]
        if let ffmpeg { args += ["--ffmpeg-location", ffmpeg] }
        args += cookies.args
        let cap = quality.height.map { "[height<=\($0)]" } ?? ""
        if ffmpeg != nil {
            args += ["-f", "bv*\(cap)+ba/b\(cap)", "--merge-output-format", "mp4"]
        } else {
            args += ["-f", "b\(cap)[ext=mp4]/b\(cap)"]
        }
        args.append(url)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ytdlp)
        p.arguments = args
        p.environment = Tools.environment

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
            let cancelled = proc.terminationReason == .uncaughtSignal
            Task { @MainActor in self?.finished(code: code, cancelled: cancelled) }
        }

        progress = 0
        errorLines = []
        status = "다운로드 중…"
        phase = .downloading
        do {
            try p.run()
            process = p
        } catch {
            phase = .ready
            status = "실행하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func cancel() { process?.terminate() }

    func openFolder() { NSWorkspace.shared.open(folder) }

    private func consume(_ text: String) {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("ERROR:") {
            errorLines.append(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
        }
        // "[download]  42.3% of ..." 에서 퍼센트를 읽는다.
        guard let range = text.range(of: #"\[download\]\s+([0-9.]+)%"#, options: .regularExpression) else { return }
        let digits = text[range].filter { "0123456789.".contains($0) }
        if let v = Double(digits) { progress = v / 100 }
    }

    private func finished(code: Int32, cancelled: Bool) {
        process = nil
        phase = .ready
        if cancelled {
            status = "취소했습니다."
        } else if code == 0 {
            progress = 1
            status = "완료! \(folder.lastPathComponent) 폴더에 저장했습니다."
            notify("다운로드 완료", title.isEmpty ? folder.lastPathComponent : title)
        } else {
            let reason = errorLines.last.map { String($0.prefix(160)) } ?? "코드 \(code)"
            status = "실패: \(reason)"
            notify("다운로드 실패", reason)
        }
    }
}

// MARK: - 메인 화면

struct MenuView: View {
    @ObservedObject var dl: Downloader

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("영상이 있는 페이지 주소", text: $dl.urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { dl.fetchInfo() }
                Button("조회") { dl.fetchInfo() }
                    .disabled(dl.phase == .fetching || dl.phase == .downloading || dl.urlText.isEmpty)
            }

            if !dl.title.isEmpty {
                Text(dl.title).font(.headline).lineLimit(2)
            }

            if dl.phase == .ready || dl.phase == .downloading {
                Picker("화질", selection: $dl.quality) {
                    ForEach(dl.qualities) { Text($0.label).tag($0) }
                }
                .disabled(dl.phase == .downloading)
            }

            Picker("쿠키", selection: $dl.cookies) {
                ForEach(CookieSource.allCases) { Text($0.label).tag($0) }
            }

            HStack {
                Text(dl.folder.path).lineLimit(1).truncationMode(.middle)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("폴더 선택…") { dl.chooseFolder() }
            }

            HStack {
                if dl.phase == .downloading {
                    Button("취소") { dl.cancel() }
                } else {
                    Button("다운로드") { dl.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(dl.phase != .ready)
                }
                Button("폴더 열기") { dl.openFolder() }
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
            }

            if dl.phase == .fetching { ProgressView().controlSize(.small) }
            if dl.phase == .downloading || dl.progress > 0 { ProgressView(value: dl.progress) }
            Text(dl.status).font(.callout)

            HStack {
                Text(dl.ytdlpVersion.isEmpty ? "yt-dlp 없음" : "yt-dlp \(dl.ytdlpVersion)")
                    .font(.caption).foregroundStyle(.secondary)
                Button(dl.updating ? "갱신 중…" : "yt-dlp 갱신") { dl.updateYtdlp() }
                    .controlSize(.small)
                    .disabled(dl.updating || dl.phase == .downloading)
            }

            if dl.ytdlp == nil {
                Text("yt-dlp를 찾을 수 없습니다. 위의 갱신 버튼을 누르세요.")
                    .foregroundStyle(.red).font(.caption)
            } else if dl.ffmpeg == nil {
                Text("ffmpeg가 없어 1080p 이상은 못 받을 수 있습니다. 터미널에서 brew install ffmpeg")
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { dl.pasteFromClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            dl.pasteFromClipboard()
        }
    }
}

@main
struct VideoGrabberApp: App {
    @StateObject private var dl = Downloader()

    var body: some Scene {
        WindowGroup("VideoGrabber") {
            MenuView(dl: dl)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
    }
}
