import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let appState: AppState
    private var statusObserver: AnyCancellable?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configurePopover()
        configureStatusItem()
        statusObserver = appState.$status.combineLatest(appState.$isLogging).sink { [weak self] status, logging in
            self?.statusItem.button?.image = NSImage(systemSymbolName: status.isConnected && logging ? "keyboard.fill" : "keyboard", accessibilityDescription: "P31n Insight")
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        let height = min(780, (NSScreen.main?.visibleFrame.height ?? 860) - 40)
        popover.contentSize = NSSize(width: 560, height: height)
        popover.contentViewController = NSHostingController(
            rootView: ScrollView {
                MenuView().environmentObject(appState)
            }.frame(width: 560, height: height)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: appState.status.isConnected && appState.isLogging ? "keyboard.fill" : "keyboard",
            accessibilityDescription: "P31n Insight"
        )
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
