import Foundation
import ReaderEngine

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

@MainActor
final class ConversionQueue: ObservableObject {
    enum Status {
        case pending
        case running(Double)
        case done(ConversionSummary)
        case skipped
        case cancelled
        case failed(String)
    }

    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        var status: Status = .pending
    }

    @Published var items: [Item] = []
    @Published var isRunning = false
    @Published var pageMarkers = true
    @Published var structureMarkers = true
    @Published var cleanNoise = true
    @Published var forceOCR = false
    @Published var overwrite = false

    private var flag = CancelFlag()

    var pendingCount: Int {
        items.filter { if case .pending = $0.status { return true } else { return false } }.count
    }

    func add(_ urls: [URL]) {
        let known = Set(items.map { $0.url.standardizedFileURL.path })
        for url in Converter.expand(urls) where !known.contains(url.standardizedFileURL.path) {
            items.append(Item(url: url))
        }
    }

    func clear() {
        guard !isRunning else { return }
        items.removeAll()
    }

    func cancel() {
        flag.cancel()
    }

    func start() {
        guard !isRunning, pendingCount > 0 else { return }
        isRunning = true
        let flag = CancelFlag()
        self.flag = flag

        var options = ConversionOptions()
        options.build.pageMarkers = pageMarkers
        options.build.structureMarkers = structureMarkers
        options.build.cleanNoise = cleanNoise
        options.forceOCR = forceOCR
        options.overwrite = overwrite

        Task {
            while !flag.isCancelled, let next = nextPending() {
                let id = next.id
                let url = next.url
                setStatus(id, .running(0))
                let outcome = await Task.detached(priority: .userInitiated) {
                    Converter.convert(
                        pdf: url,
                        options: options,
                        progress: { value in
                            Task { @MainActor in self.updateProgress(id, value) }
                        },
                        isCancelled: { flag.isCancelled })
                }.value
                switch outcome {
                case .converted(let summary): setStatus(id, .done(summary))
                case .skipped: setStatus(id, .skipped)
                case .cancelled: setStatus(id, .cancelled)
                case .failed(let message): setStatus(id, .failed(message))
                }
            }
            isRunning = false
        }
    }

    private func nextPending() -> Item? {
        items.first { if case .pending = $0.status { return true } else { return false } }
    }

    private func setStatus(_ id: UUID, _ status: Status) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].status = status
    }

    private func updateProgress(_ id: UUID, _ value: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if case .running = items[i].status {
            items[i].status = .running(value)
        }
    }
}
