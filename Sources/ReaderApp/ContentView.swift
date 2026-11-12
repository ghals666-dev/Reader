import AppKit
import ReaderEngine
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var queue: ConversionQueue
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            options
            Divider()
            list
            Divider()
            controls
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in queue.add([url]) }
                }
            }
            return true
        }
    }

    private var options: some View {
        HStack(spacing: 18) {
            Toggle("쪽 마커 [p.N]", isOn: $queue.pageMarkers)
            Toggle("소제목·인용 표시", isOn: $queue.structureMarkers)
            Toggle("항상 OCR", isOn: $queue.forceOCR)
            Toggle("기존 txt 덮어쓰기", isOn: $queue.overwrite)
            Spacer()
        }
        .toggleStyle(.checkbox)
        .disabled(queue.isRunning)
        .padding(12)
    }

    @ViewBuilder
    private var list: some View {
        if queue.items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("PDF 파일이나 폴더를 여기에 끌어다 놓으세요")
                    .font(.title3)
                Text("txt는 원본 PDF 옆에 같은 이름으로 저장됩니다")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        } else {
            List(queue.items) { item in
                ItemRow(item: item)
            }
            .background(dropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        }
    }

    private var controls: some View {
        HStack {
            Button("파일 추가…") { openPanel() }
            Button("목록 비우기") { queue.clear() }
                .disabled(queue.isRunning || queue.items.isEmpty)
            Spacer()
            Text(summaryText).foregroundStyle(.secondary)
            if queue.isRunning {
                Button("취소") { queue.cancel() }
            } else {
                Button("변환 시작") { queue.start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(queue.pendingCount == 0)
            }
        }
        .padding(12)
    }

    private var summaryText: String {
        let total = queue.items.count
        guard total > 0 else { return "" }
        return "대기 \(queue.pendingCount) / 전체 \(total)"
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.pdf]
        if panel.runModal() == .OK {
            queue.add(panel.urls)
        }
    }
}

private struct ItemRow: View {
    let item: ConversionQueue.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer()
                statusLabel
            }
            if case .running(let value) = item.status {
                ProgressView(value: value)
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .pending:
            Text("대기").foregroundStyle(.secondary)
        case .running(let value):
            Text("\(Int(value * 100))%").monospacedDigit()
        case .done:
            Label("완료", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Label("건너뜀", systemImage: "arrow.uturn.right.circle").foregroundStyle(.secondary)
        case .cancelled:
            Label("취소됨", systemImage: "xmark.circle").foregroundStyle(.secondary)
        case .failed:
            Label("실패", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private var detail: String? {
        switch item.status {
        case .done(let s):
            var parts = ["\(s.pageCount)쪽 (OCR \(s.ocrPages), 텍스트 \(s.textLayerPages))"]
            if !s.lowConfidencePages.isEmpty {
                parts.append("인식이 불확실한 쪽: " + s.lowConfidencePages.map(String.init).joined(separator: ", "))
            }
            if !s.emptyPages.isEmpty {
                parts.append("빈 쪽: " + s.emptyPages.map(String.init).joined(separator: ", "))
            }
            return parts.joined(separator: " · ")
        case .skipped:
            return "같은 이름의 txt가 이미 있습니다"
        case .failed(let message):
            return message
        default:
            return nil
        }
    }
}
