import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState

    private var contentHeight: CGFloat {
        var h = PanelMetrics.barHeight
        if state.leftExpanded { h = max(h, PanelMetrics.drawerHeight) }
        if state.rightExpanded { h = max(h, PanelMetrics.menuHeight) }
        return h
    }

    private var leftW: CGFloat { state.leftExpanded ? PanelMetrics.drawerWidth : 0 }
    private var rightW: CGFloat { state.rightExpanded ? PanelMetrics.menuWidth : 0 }
    private var gapL: CGFloat { state.leftExpanded ? PanelMetrics.gap : 0 }
    private var gapR: CGFloat { state.rightExpanded ? PanelMetrics.gap : 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            if state.leftExpanded {
                ShotsDrawer()
                    .frame(width: leftW, height: contentHeight)
                    .transition(.opacity)
                Spacer(minLength: 0).frame(width: gapL)
            }

            VStack(spacing: 0) {
                ControlBar()
                    .frame(width: PanelMetrics.barWidth, height: PanelMetrics.barHeight)
                Spacer(minLength: 0)
            }
            .frame(width: PanelMetrics.barWidth, height: contentHeight, alignment: .top)
            .overlay(alignment: .top) {
                toastView.offset(y: PanelMetrics.barHeight + 8)
            }

            if state.rightExpanded {
                Spacer(minLength: 0).frame(width: gapR)
                AppsMenu()
                    .frame(width: rightW, height: contentHeight)
                    .transition(.opacity)
            }
        }
        .frame(
            width: leftW + gapL + PanelMetrics.barWidth + gapR + rightW,
            height: contentHeight,
            alignment: .topLeading
        )
        .animation(.easeOut(duration: PanelMetrics.animDuration), value: state.leftExpanded)
        .animation(.easeOut(duration: PanelMetrics.animDuration), value: state.rightExpanded)
        .animation(.easeOut(duration: PanelMetrics.animDuration), value: state.toast)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = state.toast {
            HStack(spacing: 7) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.blue)
                Text(toast)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: PanelMetrics.barWidth - 16)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.80))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}
