import SwiftUI
import AppKit

// MARK: - Palette

enum Palette {
    static let green  = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let red    = Color(red: 1.00, green: 0.30, blue: 0.26)
    static let blue   = Color(red: 0.06, green: 0.53, blue: 1.00)
    static let amber  = Color(red: 1.00, green: 0.72, blue: 0.20)
    static let purple = Color(red: 0.65, green: 0.45, blue: 1.00)

    static let textPrimary   = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary  = Color.white.opacity(0.36)

    static let card      = Color.white.opacity(0.07)
    static let cardHover = Color.white.opacity(0.12)
    static let stroke    = Color.white.opacity(0.10)
    static let strokeSoft = Color.white.opacity(0.06)
    static let well      = Color.black.opacity(0.22)
}

// MARK: - Panel metrics

/// Named `PanelMetrics` (not `Layout`) so it does not shadow SwiftUI's `Layout` protocol.
enum PanelMetrics {
    static let barWidth: CGFloat = 320
    static let barHeight: CGFloat = 56
    static let drawerWidth: CGFloat = 306
    static let drawerHeight: CGFloat = 452
    static let menuWidth: CGFloat = 348
    static let menuHeight: CGFloat = 508
    static let gap: CGFloat = 8
    static let corner: CGFloat = 18
    static let animDuration: Double = 0.24
}

// MARK: - Glass background

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
        nsView.state = .active
    }
}

struct GlassPanel: ViewModifier {
    var corner: CGFloat = PanelMetrics.corner

    func body(content: Content) -> some View {
        content
            .background(VisualEffectBackground(material: .hudWindow))
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func glassPanel(corner: CGFloat = PanelMetrics.corner) -> some View {
        modifier(GlassPanel(corner: corner))
    }
}

// MARK: - Drag coordination

/// Suppresses a button's action when the press was actually a window drag.
final class DragState: ObservableObject {
    static let shared = DragState()
    @Published var isDragging = false
    private var suppressUntil = Date.distantPast

    func started() {
        isDragging = true
    }

    func ended() {
        isDragging = false
        suppressUntil = Date().addingTimeInterval(0.18)
    }

    /// True if a control should ignore its tap because a drag just happened.
    func shouldSuppressTap() -> Bool {
        isDragging || Date() < suppressUntil
    }
}

// MARK: - Buttons

struct HoverIconButton: View {
    let systemName: String
    var size: CGFloat = 30
    var iconSize: CGFloat = 13
    var tint: Color = Palette.textPrimary
    var fill: Color = Color.white.opacity(0.10)
    var hoverFill: Color = Color.white.opacity(0.20)
    var help: String = ""
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @ObservedObject private var dragState = DragState.shared

    var body: some View {
        Button {
            if dragState.shouldSuppressTap() { return }
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(hovering && !disabled ? hoverFill : fill)
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(disabled ? Palette.textTertiary : tint)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The big round transport controls (Play / Stop).
struct TransportButton: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 36
    var help: String = ""
    var pulsing: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @State private var pulse = false
    @ObservedObject private var dragState = DragState.shared

    var body: some View {
        Button {
            if dragState.shouldSuppressTap() { return }
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: tint.opacity(hovering ? 0.55 : 0.32), radius: hovering ? 9 : 5, y: 1)

                if pulsing {
                    Circle()
                        .stroke(tint.opacity(0.55), lineWidth: 2)
                        .scaleEffect(pulse ? 1.5 : 1.0)
                        .opacity(pulse ? 0 : 0.9)
                }

                Image(systemName: systemName)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: systemName == "play.fill" ? 1.2 : 0)
            }
            .frame(width: size, height: size)
            .scaleEffect(hovering && !disabled ? 1.07 : 1.0)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hovering = $0 }
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .help(help)
    }
}

/// Collapse / expand chevron.
struct DisclosureArrow: View {
    let expanded: Bool
    let pointsLeft: Bool          // which way the arrow points when collapsed
    var tint: Color = Palette.textPrimary
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false
    @ObservedObject private var dragState = DragState.shared

    private var icon: String {
        if expanded {
            return pointsLeft ? "chevron.right" : "chevron.left"
        } else {
            return pointsLeft ? "chevron.left" : "chevron.right"
        }
    }

    var body: some View {
        Button {
            if dragState.shouldSuppressTap() { return }
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.20) : Color.white.opacity(0.10))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 28, height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Small pieces

struct StatusDot: View {
    let color: Color
    var pulsing = false
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.7), radius: 4)
            .opacity(pulsing ? (on ? 0.35 : 1) : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = Palette.textSecondary
    var background: Color = Color.white.opacity(0.09)
    var mono = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: mono ? .monospaced : .default))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(background)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

struct ThinDivider: View {
    var vertical = true
    var body: some View {
        Rectangle()
            .fill(Palette.stroke)
            .frame(width: vertical ? 1 : nil, height: vertical ? 20 : 1)
    }
}
