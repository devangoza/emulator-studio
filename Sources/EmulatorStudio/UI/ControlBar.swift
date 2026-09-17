import SwiftUI

/// The draggable control group: Play / Stop / Close, with a collapse arrow on each side.
struct ControlBar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var emulators: EmulatorManager

    @ObservedObject private var dragState = DragState.shared

    var body: some View {
        HStack(spacing: 6) {

            // ── Left: screenshots drawer ────────────────────────────────
            DisclosureArrow(
                expanded: state.leftExpanded,
                pointsLeft: true,
                help: state.leftExpanded ? "Hide screenshots" : "Show screenshots"
            ) {
                PanelController.shared.toggleLeft()
            }

            HoverIconButton(
                systemName: "camera.fill",
                size: 30,
                iconSize: 13,
                tint: Palette.blue,
                help: "Capture screenshot",
                disabled: !emulators.hasReadyDevice
            ) {
                Task { await state.capturePressed() }
            }

            ThinDivider()

            // ── Centre: transport ───────────────────────────────────────
            TransportButton(
                systemName: "play.fill",
                tint: Palette.green,
                help: "Start Android emulator",
                pulsing: emulators.isBooting,
                disabled: emulators.hasReadyDevice || emulators.isBooting
            ) {
                Task { await state.playPressed() }
            }

            TransportButton(
                systemName: "stop.fill",
                tint: Palette.red,
                size: 32,
                help: "Stop emulator",
                disabled: !emulators.hasReadyDevice && !emulators.isBooting
            ) {
                Task { await state.stopPressed() }
            }

            HoverIconButton(
                systemName: "xmark",
                size: 28,
                iconSize: 11,
                tint: Palette.textSecondary,
                help: "Quit Emulator Studio"
            ) {
                state.quit()
            }

            ThinDivider()

            // ── Right: status + apps menu ───────────────────────────────
            statusPill

            DisclosureArrow(
                expanded: state.rightExpanded,
                pointsLeft: false,
                help: state.rightExpanded ? "Hide Flutter apps" : "Show Flutter apps"
            ) {
                PanelController.shared.toggleRight()
            }
        }
        .padding(.horizontal, 9)
        .frame(width: PanelMetrics.barWidth, height: PanelMetrics.barHeight)
        .glassPanel()
        .simultaneousGesture(dragGesture)
    }

    // MARK: - Status pill

    private var statusPill: some View {
        HStack(spacing: 5) {
            StatusDot(color: statusColor, pulsing: emulators.isBooting)
            Text(statusText)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(
            Capsule().fill(Color.white.opacity(0.07))
        )
        .overlay(
            Capsule().strokeBorder(Palette.strokeSoft, lineWidth: 1)
        )
        .help(emulators.statusLine)
    }

    private var statusColor: Color {
        if emulators.isBooting { return Palette.amber }
        if emulators.hasReadyDevice { return Palette.green }
        if !emulators.sdkAvailable { return Palette.red }
        return Color.white.opacity(0.30)
    }

    private var statusText: String {
        if emulators.isBooting { return "Booting…" }
        if let d = emulators.activeDevice {
            let m = d.model.isEmpty ? d.serial : d.model
            return m.replacingOccurrences(of: "_", with: " ")
        }
        if !emulators.sdkAvailable { return "No SDK" }
        if !emulators.devices.isEmpty { return emulators.devices[0].state }
        return "Emulator off"
    }

    // MARK: - Window drag

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !dragState.isDragging {
                    dragState.started()
                    PanelController.shared.beginDrag()
                }
                PanelController.shared.drag(by: value.translation)
            }
            .onEnded { _ in
                PanelController.shared.endDrag()
                dragState.ended()
            }
    }
}
