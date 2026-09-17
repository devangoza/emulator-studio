import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let state = AppState.shared
        PanelController.shared.install(state: state)
        installStatusItem(state: state)

        Task { @MainActor in
            await state.bootstrap()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.emulators.stopPolling()
    }

    // MARK: - Menu bar

    private func installStatusItem(state: AppState) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "play.rectangle.on.rectangle",
                accessibilityDescription: "Emulator Studio"
            )
            button.image?.isTemplate = true
            button.toolTip = "Emulator Studio"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide Controls", action: #selector(togglePanel), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())

        let shotItem = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "s")
        shotItem.target = self
        menu.addItem(shotItem)

        let playItem = NSMenuItem(title: "Start Emulator", action: #selector(startEmulator), keyEquivalent: "r")
        playItem.target = self
        menu.addItem(playItem)

        let stopItem = NSMenuItem(title: "Stop Emulator", action: #selector(stopEmulator), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let openShots = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openShotsFolder), keyEquivalent: "")
        openShots.target = self
        menu.addItem(openShots)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Emulator Studio", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() { PanelController.shared.toggleVisibility() }

    @objc private func takeScreenshot() {
        Task { @MainActor in await AppState.shared.capturePressed() }
    }

    @objc private func startEmulator() {
        Task { @MainActor in await AppState.shared.playPressed() }
    }

    @objc private func stopEmulator() {
        Task { @MainActor in await AppState.shared.stopPressed() }
    }

    @objc private func openShotsFolder() {
        NSWorkspace.shared.open(AppState.shared.shots.rootURL)
    }

    @objc private func quitApp() {
        AppState.shared.quit()
    }
}
