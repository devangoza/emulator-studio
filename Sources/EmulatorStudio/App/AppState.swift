import Foundation
import SwiftUI
import AppKit
import Combine

/// Single source of truth shared by the panel UI.
@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    let emulators = EmulatorManager()
    let library = FlutterLibrary()
    let installer = Installer()
    let shots = ScreenshotStore()

    // Panel visibility of the two fly-outs.
    @Published var leftExpanded = false
    @Published var rightExpanded = false

    // Selection state
    @Published var selectedAvd: String = ""
    @Published var expandedProject: String?
    @Published var branchSelection: [String: String] = [:]
    @Published var variant: BuildVariant = .debug
    @Published var showLog = false
    @Published var panelVisible = true

    @Published var toast: String?
    @Published var bootstrapDone = false

    private var toastTask: Task<Void, Never>?

    // MARK: - Bootstrap

    func bootstrap() async {
        Toolchain.invalidate()
        await emulators.refresh()
        if selectedAvd.isEmpty {
            selectedAvd = emulators.avds.first?.name ?? ""
        }
        emulators.startPolling()
        await shots.reload()
        await library.scan()

        // If a project is already installed, default the screenshot folder to it.
        if shots.targetGroup == ScreenshotStore.allGroup, let first = library.projects.first {
            shots.targetGroup = first.name
        }

        bootstrapDone = true

        if !emulators.sdkAvailable {
            flash("Android SDK not found — set ANDROID_HOME or install the SDK.")
        } else if emulators.avds.isEmpty {
            flash("No AVDs found. Create one in Android Studio.")
        }
    }

    // MARK: - Emulator control

    func playPressed() async {
        if let device = emulators.activeDevice {
            flash("\(device.displayName) is already running")
            return
        }
        guard !emulators.avds.isEmpty else {
            flash("No AVD available. Create one in Android Studio.")
            return
        }
        let name = selectedAvd.isEmpty ? (emulators.avds.first?.name ?? "") : selectedAvd
        guard let avd = emulators.avds.first(where: { $0.name == name }) ?? emulators.avds.first else { return }
        await emulators.boot(avd: avd)
    }

    func stopPressed() async {
        await emulators.stopAll()
        flash("Emulator stopped")
    }

    // MARK: - Screenshots

    func capturePressed() async {
        guard let device = emulators.activeDevice else {
            flash("Start the emulator first")
            return
        }
        let group = shots.targetGroup == ScreenshotStore.allGroup
            ? (library.projects.first?.name ?? ScreenshotStore.unsortedGroup)
            : shots.targetGroup

        if let shot = await shots.capture(serial: device.serial, group: group) {
            flash("Saved to \(shot.group)")
            if !leftExpanded { leftExpanded = true }
        } else if let err = shots.lastError {
            flash(err)
        }
    }

    func captureInto(group: String) async {
        guard let device = emulators.activeDevice else {
            flash("Start the emulator first")
            return
        }
        shots.targetGroup = group
        if let shot = await shots.capture(serial: device.serial, group: group) {
            flash("Saved to \(shot.group)")
        } else if let err = shots.lastError {
            flash(err)
        }
    }

    // MARK: - Projects

    func branch(for project: FlutterProject) -> String {
        if let chosen = branchSelection[project.path], !chosen.isEmpty { return chosen }
        if let current = project.currentBranch, !current.isEmpty { return current }
        return project.branches.first ?? ""
    }

    func setBranch(_ branch: String, for project: FlutterProject) {
        branchSelection[project.path] = branch
    }

    func installPressed(_ project: FlutterProject) {
        guard let device = emulators.activeDevice else {
            flash("Start the emulator first")
            return
        }
        let branch = self.branch(for: project)
        let apkExists = Installer.existingApk(project: project, variant: variant) != nil
        let reuse = apkExists && (branch == project.currentBranch || !project.isGit)

        shots.targetGroup = project.name

        installer.install(
            project: project,
            branch: branch,
            variant: variant,
            device: device,
            reuseExistingBuild: reuse
        )
        showLog = true
    }

    func canInstall(_ project: FlutterProject) -> Bool {
        !installer.isBusy && emulators.activeDevice != nil
    }

    // MARK: - Toast

    func flash(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            toast = message
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
            }
        }
    }

    // MARK: - Quit

    func quit() {
        emulators.stopPolling()
        NSApplication.shared.terminate(nil)
    }
}
