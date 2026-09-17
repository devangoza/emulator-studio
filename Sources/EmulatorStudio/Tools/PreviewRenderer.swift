import AppKit
import SwiftUI

/// Renders the full panel UI to a PNG without needing screen-recording permission.
/// Usage:  EmulatorStudio --render [outputPath]
@MainActor
enum PreviewRenderer {

    static var isRequested: Bool {
        CommandLine.arguments.contains("--render")
    }

    static func outputPath() -> String {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--render"), idx + 1 < args.count {
            let candidate = args[idx + 1]
            if !candidate.hasPrefix("-") { return candidate }
        }
        return "build/preview.png"
    }

    /// Kicks off the render; the caller is responsible for running the app run loop.
    static func start() {
        let state = AppState.shared

        Task { @MainActor in
            await state.bootstrap()

            // Open both fly-outs and expand the first project so everything is visible.
            state.leftExpanded = true
            state.rightExpanded = true
            if let first = state.library.projects.first {
                state.expandedProject = first.path
                state.branchSelection[first.path] = first.branches.dropFirst().first ?? first.currentBranch ?? ""
            }
            state.toast = "Drag the bar anywhere"

            // Let SwiftUI settle.
            try? await Task.sleep(nanoseconds: 900_000_000)

            write(state: state)
            exit(0)
        }
    }

    private static func write(state: AppState) {
        let width = PanelMetrics.drawerWidth + PanelMetrics.gap
                  + PanelMetrics.barWidth
                  + PanelMetrics.gap + PanelMetrics.menuWidth
        let height = max(PanelMetrics.barHeight,
                         max(PanelMetrics.drawerHeight, PanelMetrics.menuHeight))
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        let root = RootView()
            .environmentObject(state)
            .environmentObject(state.emulators)
            .environmentObject(state.library)
            .environmentObject(state.installer)
            .environmentObject(state.shots)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = rect
        hosting.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write(Data("render: could not create bitmap\n".utf8))
            exit(1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        // Composite over a desktop-like backdrop, since the HUD glass is translucent.
        let out = NSImage(size: NSSize(width: width, height: height))
        out.lockFocus()
        let backdrop = NSGradient(colors: [
            NSColor(srgbRed: 0.20, green: 0.23, blue: 0.29, alpha: 1),
            NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        ])
        backdrop?.draw(in: rect, angle: -90)
        if let cg = rep.cgImage {
            NSImage(cgImage: cg, size: NSSize(width: width, height: height)).draw(in: rect)
        }
        out.unlockFocus()

        guard let tiff = out.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render: could not encode PNG\n".utf8))
            exit(1)
        }

        let path = outputPath()
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try png.write(to: url)
            print("wrote \(url.path)  (\(Int(width))×\(Int(height)))")
        } catch {
            FileHandle.standardError.write(Data("render: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
