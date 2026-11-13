import AppKit
import SwiftUI

@main
struct ReaderApp: App {
    @StateObject private var queue = ConversionQueue()

    var body: some Scene {
        WindowGroup("Reader") {
            ContentView()
                .environmentObject(queue)
                .frame(minWidth: 720, minHeight: 460)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}
