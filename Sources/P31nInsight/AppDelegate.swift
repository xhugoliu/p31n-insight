import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState(preview: CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--render-preview"))
    private var statusBarController: StatusBarController?
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), index + 1 < CommandLine.arguments.count {
            renderPreview(to: CommandLine.arguments[index + 1])
            return
        }
        statusBarController = StatusBarController(appState: appState)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.shutdown()
    }

    private func renderPreview(to path: String) {
        let view = NSHostingView(rootView: MenuView().environmentObject(appState))
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 850)
        view.appearance = NSAppearance(named: .aqua)
        let height = max(600, min(view.fittingSize.height, 1000))
        view.frame.size.height = height
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        previewWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
            NSApplication.shared.terminate(nil)
        }
    }
}
