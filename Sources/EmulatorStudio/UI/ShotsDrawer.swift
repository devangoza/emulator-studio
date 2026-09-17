import SwiftUI
import AppKit

/// Cheap in-memory cache so the grid doesn't re-decode PNGs on every redraw.
final class ThumbCache {
    static let shared = ThumbCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func evict(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }
}

// MARK: - Drawer

struct ShotsDrawer: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var shots: ScreenshotStore
    @EnvironmentObject var emulators: EmulatorManager

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            groupStrip
            hairline
            grid
            hairline
            footer
        }
        .frame(width: PanelMetrics.drawerWidth, height: PanelMetrics.drawerHeight)
        .glassPanel()
        .task { await shots.reload() }
    }

    private var hairline: some View {
        Rectangle().fill(Palette.strokeSoft).frame(height: 1)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.blue)

            Text("Screenshots")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.textPrimary)

            Text("\(shots.filteredShots.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)

            Spacer(minLength: 0)

            HoverIconButton(systemName: "arrow.clockwise", size: 24, iconSize: 11,
                            help: "Reload screenshots") {
                Task { await shots.reload() }
            }

            HoverIconButton(systemName: "folder", size: 24, iconSize: 11,
                            help: "Open screenshots folder") {
                NSWorkspace.shared.open(shots.rootURL)
            }

            HoverIconButton(systemName: "camera.fill", size: 24, iconSize: 11,
                            tint: Palette.blue,
                            help: "Capture screenshot",
                            disabled: !emulators.hasReadyDevice) {
                Task { await state.capturePressed() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Group strip

    private var groupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                groupChip(ScreenshotStore.allGroup, count: shots.shots.count)

                ForEach(shots.groups, id: \.self) { group in
                    groupChip(group, count: shots.shots.filter { $0.group == group }.count)
                }

                if shots.groups.isEmpty {
                    Text("no folders yet")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func groupChip(_ name: String, count: Int) -> some View {
        let selected = shots.selectedGroup == name
        let isTarget = shots.targetGroup == name
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                shots.selectedGroup = name
            }
        } label: {
            HStack(spacing: 5) {
                if isTarget {
                    Circle().fill(Palette.blue).frame(width: 5, height: 5)
                }
                Text(name)
                    .font(.system(size: 10.5, weight: selected ? .bold : .medium))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .opacity(0.6)
            }
            .foregroundStyle(selected ? Color.white : Palette.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? Palette.blue.opacity(0.85) : Palette.card)
            )
            .overlay(
                Capsule().strokeBorder(isTarget && !selected ? Palette.blue.opacity(0.4) : Palette.strokeSoft,
                                       lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Capture into “\(name)”") {
                Task { await state.captureInto(group: name) }
            }
            if name != ScreenshotStore.allGroup {
                Button("Set as capture target") { shots.targetGroup = name }
                Divider()
                Button("Move all to Trash", role: .destructive) { shots.clearGroup(name) }
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        Group {
            if shots.filteredShots.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(shots.filteredShots) { shot in
                            ShotCard(shot: shot)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emulators.hasReadyDevice ? "camera.viewfinder" : "iphone.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text(emulators.hasReadyDevice ? "No screenshots yet" : "Emulator is not running")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(emulators.hasReadyDevice
                 ? "Press the camera button to capture the emulator screen."
                 : "Press Play to start the emulator, then capture.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
            Text("Drag a shot anywhere · saving to “\(shots.targetGroup)”")
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

// MARK: - Shot card

struct ShotCard: View {
    let shot: Shot

    @EnvironmentObject var shots: ScreenshotStore
    @State private var hovering = false

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: shot.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.well)

                if let image = ThumbCache.shared.image(for: shot.url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(3)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(height: 172)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(hovering ? Palette.blue.opacity(0.6) : Palette.strokeSoft, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if hovering {
                    HStack(spacing: 4) {
                        miniAction("doc.on.doc", help: "Copy image") { shots.copyToClipboard(shot) }
                        miniAction("magnifyingglass", help: "Open") { shots.open(shot) }
                        miniAction("trash", help: "Move to Trash") { shots.delete(shot) }
                    }
                    .padding(5)
                    .background(Capsule().fill(Color.black.opacity(0.62)))
                    .padding(5)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if hovering {
                    HStack(spacing: 3) {
                        Image(systemName: "hand.draw.fill").font(.system(size: 8))
                        Text("drag out").font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.blue.opacity(0.9)))
                    .padding(5)
                    .transition(.opacity)
                }
            }

            HStack(spacing: 4) {
                Text(timeLabel)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                if shots.selectedGroup == ScreenshotStore.allGroup {
                    Text(shot.group)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .onDrag {
            if let provider = NSItemProvider(contentsOf: shot.url) {
                return provider
            }
            return NSItemProvider(object: shot.url as NSURL)
        }
        .contextMenu {
            Button("Open") { shots.open(shot) }
            Button("Copy Image") { shots.copyToClipboard(shot) }
            Button("Copy Path") { shots.copyPath(shot) }
            Divider()
            Button("Reveal in Finder") { shots.reveal(shot) }
            Divider()
            Button("Move to Trash", role: .destructive) { shots.delete(shot) }
        }
        .help("\(shot.fileName)\nDrag to Finder, Slack, Notes — anywhere")
    }

    private func miniAction(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
