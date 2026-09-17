import SwiftUI

// MARK: - Flow layout for branch chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Apps menu

struct AppsMenu: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var library: FlutterLibrary
    @EnvironmentObject var installer: Installer
    @EnvironmentObject var emulators: EmulatorManager

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    deviceSection
                    avdSection
                    projectsSection
                    if installer.activeJob != nil || !installer.jobs.isEmpty {
                        logSection
                    }
                }
                .padding(12)
            }

            hairline
            footer
        }
        .frame(width: PanelMetrics.menuWidth, height: PanelMetrics.menuHeight)
        .glassPanel()
    }

    private var hairline: some View {
        Rectangle().fill(Palette.strokeSoft).frame(height: 1)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.purple)

            Text("Flutter Apps")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.textPrimary)

            if library.isScanning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }

            Spacer(minLength: 0)

            HoverIconButton(systemName: "arrow.clockwise", size: 24, iconSize: 11,
                            help: "Rescan folders") {
                Task { await library.scan() }
            }

            HoverIconButton(systemName: "folder.badge.plus", size: 24, iconSize: 11,
                            help: "Add a project folder") {
                addFolder()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders that contain Flutter projects"
        if panel.runModal() == .OK {
            for url in panel.urls {
                library.addRoot(url.path)
            }
            Task { await library.scan() }
        }
    }

    // MARK: Device

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: "Target device")

            if let device = emulators.activeDevice {
                HStack(spacing: 8) {
                    StatusDot(color: Palette.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(device.serial)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Chip(text: "ready", tint: Palette.green, background: Palette.green.opacity(0.16))
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card))
            } else {
                HStack(spacing: 8) {
                    StatusDot(color: emulators.isBooting ? Palette.amber : Color.white.opacity(0.3),
                              pulsing: emulators.isBooting)
                    Text(emulators.isBooting ? "Starting emulator…" : "No device — press Play")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card))
            }
        }
    }

    // MARK: AVD

    private var avdSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: "Emulator (AVD)")

            if emulators.avds.isEmpty {
                Text(emulators.sdkAvailable
                     ? "No AVDs found. Create one in Android Studio."
                     : "Android SDK not found. Set ANDROID_HOME.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(emulators.avds) { avd in
                        SelectChip(
                            text: avd.name,
                            selected: state.selectedAvd == avd.name
                        ) {
                            state.selectedAvd = avd.name
                        }
                    }
                }
            }

            Toggle(isOn: $emulators.headless) {
                Text("Headless (no emulator window)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    // MARK: Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Projects",
                trailing: AnyView(
                    Text("\(library.projects.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                )
            )

            if library.projects.isEmpty && !library.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Flutter projects found.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                    Text("Add a folder with the + button, or make sure your project has a pubspec.yaml and an android/ directory.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card))
            }

            ForEach(library.projects) { project in
                ProjectRow(project: project)
            }
        }
    }

    // MARK: Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(
                title: "Build log",
                trailing: AnyView(
                    Button {
                        installer.clearFinished()
                        state.showLog = false
                    } label: {
                        Text("clear")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.blue)
                    }
                    .buttonStyle(.plain)
                )
            )

            if let job = installer.jobs.last {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if job.stage.isBusy {
                            ProgressView().controlSize(.mini).scaleEffect(0.7)
                        } else if case .failed = job.stage {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.red)
                        } else if job.stage == .done {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.green)
                        }
                        Text("\(job.projectName) · \(job.branch) · \(job.variant.title)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(job.stage.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(stageColor(job.stage))
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(job.log.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(Palette.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(idx)
                                }
                            }
                            .padding(7)
                        }
                        .frame(height: 108)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.well))
                        .onChange(of: job.log.count) { _ in
                            withAnimation(.linear(duration: 0.15)) {
                                proxy.scrollTo(job.log.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card))
            }
        }
    }

    private func stageColor(_ stage: InstallStage) -> Color {
        switch stage {
        case .done:            return Palette.green
        case .failed:          return Palette.red
        case .idle:            return Palette.textTertiary
        default:               return Palette.amber
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
            Text(rootSummary)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let scanned = library.lastScan {
                Text(shortTime(scanned))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            Text("Scan folders")
            Divider()
            ForEach(library.roots, id: \.self) { root in
                Button("Remove \(root)") { library.removeRoot(root) }
            }
        }
        .help(library.roots.joined(separator: "\n"))
    }

    private var rootSummary: String {
        let folders = library.roots.count
        let projects = library.projects.count
        let f = "\(folders) folder\(folders == 1 ? "" : "s")"
        let p = "\(projects) project\(projects == 1 ? "" : "s")"
        return "\(f) scanned · \(p)"
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Select chip

struct SelectChip: View {
    let text: String
    let selected: Bool
    var tint: Color = Palette.blue
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 10.5, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Color.white : Palette.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? tint.opacity(0.85) : (hovering ? Palette.cardHover : Palette.card))
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Color.clear : Palette.strokeSoft, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Project row

struct ProjectRow: View {
    let project: FlutterProject

    @EnvironmentObject var state: AppState
    @EnvironmentObject var installer: Installer
    @EnvironmentObject var emulators: EmulatorManager

    @State private var hovering = false

    private var expanded: Bool { state.expandedProject == project.path }
    private var selectedBranch: String { state.branch(for: project) }

    private var jobForProject: InstallJob? {
        installer.jobs.last { $0.projectPath == project.path }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            summaryRow

            if expanded {
                branchSection
                variantSection
                actionSection

                if let job = jobForProject, job.stage.isBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).scaleEffect(0.65)
                        Text(job.stage.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.amber)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering || expanded ? Palette.cardHover : Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(expanded ? Palette.blue.opacity(0.35) : Palette.strokeSoft, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    private var summaryRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                state.expandedProject = expanded ? nil : project.path
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(project.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text((project.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)

                if project.isGit {
                    Chip(
                        text: project.currentBranch ?? "detached",
                        tint: Palette.purple,
                        background: Palette.purple.opacity(0.16),
                        mono: true
                    )
                } else {
                    Chip(text: "no git")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                Text("Branch to build")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
                if project.branches.count > 6 {
                    Text("\(project.branches.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            if project.branches.isEmpty {
                Text(project.isGit ? "No branches found." : "Not a git repository — builds the working copy.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                ScrollView(.vertical, showsIndicators: project.branches.count > 8) {
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(project.branches, id: \.self) { branch in
                            SelectChip(
                                text: branch,
                                selected: selectedBranch == branch,
                                tint: Palette.purple
                            ) {
                                state.setBranch(branch, for: project)
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxHeight: project.branches.count > 8 ? 96 : nil)

                if selectedBranch != project.currentBranch, project.isGit {
                    HStack(spacing: 5) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.green)
                        Text("Builds in an isolated workspace — your checkout stays on \(project.currentBranch ?? "HEAD").")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var variantSection: some View {
        HStack(spacing: 6) {
            Text("Build")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)

            ForEach(BuildVariant.allCases) { variant in
                SelectChip(text: variant.title, selected: state.variant == variant, tint: Palette.blue) {
                    state.variant = variant
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actionSection: some View {
        let ready = emulators.activeDevice != nil
        let canInstall = !installer.isBusy && ready

        return VStack(spacing: 6) {
            Button {
                state.installPressed(project)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(canInstall ? "Build & install on \(emulators.activeDevice?.model ?? "device")"
                                    : (ready ? "Busy…" : "Start the emulator first"))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(canInstall ? Color.white : Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(canInstall ? Palette.blue.opacity(0.85) : Color.white.opacity(0.07))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canInstall)

            if let apk = Installer.existingApk(project: project, variant: state.variant) {
                Button {
                    guard let device = emulators.activeDevice else { return }
                    installer.install(
                        project: project,
                        branch: project.currentBranch ?? "",
                        variant: state.variant,
                        device: device,
                        reuseExistingBuild: true
                    )
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill").font(.system(size: 9))
                        Text("Reinstall last build")
                            .font(.system(size: 10, weight: .medium))
                        Spacer(minLength: 0)
                        Text((apk as NSString).lastPathComponent)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .disabled(!canInstall)
                .opacity(canInstall ? 1 : 0.45)
            }
        }
    }
}
