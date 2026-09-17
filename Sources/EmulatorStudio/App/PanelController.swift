import AppKit
import SwiftUI

/// A borderless floating panel that can take key focus without activating the app,
/// so the emulator window keeps focus while you use the controls.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {

    static let shared = PanelController()

    private(set) var panel: FloatingPanel!

    /// Anchor: the *left* edge and *top* edge of the control bar, in AppKit screen coords.
    private var barLeft: CGFloat = 0
    private var barTop: CGFloat = 0

    private var dragStartPanelOrigin: CGPoint = .zero
    private var state: AppState?

    private init() {}

    // MARK: - Setup

    func install(state: AppState) {
        self.state = state

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.barWidth, height: PanelMetrics.barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.worksWhenModal = true
        panel.title = "Emulator Studio"
        // The HUD material is always dark; pin the appearance so text stays readable.
        panel.appearance = NSAppearance(named: .darkAqua)

        self.panel = panel

        // Host the SwiftUI tree.
        let root = RootView()
            .environmentObject(state)
            .environmentObject(state.emulators)
            .environmentObject(state.library)
            .environmentObject(state.installer)
            .environmentObject(state.shots)

        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Initial position: top-centre of the main screen.
        if let screen = NSScreen.main {
            barLeft = screen.frame.midX - PanelMetrics.barWidth / 2
            barTop = screen.frame.maxY - 96
        }

        applyLayout(animated: false)
        panel.orderFrontRegardless()
    }

    // MARK: - Layout

    private var leftWidth: CGFloat {
        guard let state, state.leftExpanded else { return 0 }
        return PanelMetrics.drawerWidth + PanelMetrics.gap
    }

    private var rightWidth: CGFloat {
        guard let state, state.rightExpanded else { return 0 }
        return PanelMetrics.menuWidth + PanelMetrics.gap
    }

    private var panelHeight: CGFloat {
        guard let state else { return PanelMetrics.barHeight }
        var h = PanelMetrics.barHeight
        if state.leftExpanded { h = max(h, PanelMetrics.drawerHeight) }
        if state.rightExpanded { h = max(h, PanelMetrics.menuHeight) }
        return h
    }

    private var panelWidth: CGFloat {
        leftWidth + PanelMetrics.barWidth + rightWidth
    }

    private var targetFrame: NSRect {
        NSRect(
            x: barLeft - leftWidth,
            y: barTop - panelHeight,
            width: panelWidth,
            height: panelHeight
        )
    }

    func applyLayout(animated: Bool) {
        guard let panel else { return }
        let frame = targetFrame

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = PanelMetrics.animDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    func toggleLeft() {
        guard let state else { return }
        state.leftExpanded.toggle()
        applyLayout(animated: true)
        if state.leftExpanded { Task { await state.shots.reload() } }
    }

    func toggleRight() {
        guard let state else { return }
        state.rightExpanded.toggle()
        applyLayout(animated: true)
    }

    // MARK: - Dragging

    func beginDrag() {
        guard let panel else { return }
        dragStartPanelOrigin = panel.frame.origin
    }

    /// `translation` comes from SwiftUI's DragGesture (y grows downward).
    func drag(by translation: CGSize) {
        guard let panel else { return }
        let newOrigin = CGPoint(
            x: dragStartPanelOrigin.x + translation.width,
            y: dragStartPanelOrigin.y - translation.height
        )
        panel.setFrameOrigin(newOrigin)
        syncAnchorFromPanel()
    }

    /// Called when the gesture ends — persists the new resting position.
    func endDrag() {
        syncAnchorFromPanel()
    }

    private func syncAnchorFromPanel() {
        guard let panel else { return }
        barLeft = panel.frame.origin.x + leftWidth
        barTop = panel.frame.origin.y + panelHeight
    }

    // MARK: - Visibility

    func show() {
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggleVisibility() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
