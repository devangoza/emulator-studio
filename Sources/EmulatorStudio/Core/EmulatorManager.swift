import Foundation
import Combine

/// Owns everything Android: AVD discovery, booting emulators in the background,
/// tracking adb devices, and stopping them again.
@MainActor
final class EmulatorManager: ObservableObject {

    @Published private(set) var avds: [Avd] = []
    @Published private(set) var devices: [AndroidDevice] = []
    @Published private(set) var statusLine: String = "Idle"
    @Published private(set) var isBooting = false
    @Published private(set) var lastError: String?
    @Published var headless = false

    /// Processes we launched, keyed by AVD name.
    private var launched: [String: Process] = [:]
    private var pollTimer: Timer?
    private var bootWatchdogs: [String: Task<Void, Never>] = [:]

    private var adb: String? { Toolchain.adbBinary?.path }
    private var emulator: String? { Toolchain.emulatorBinary?.path }

    var sdkAvailable: Bool { Toolchain.androidSDK != nil }

    /// The device we consider "the" target for installs and screenshots.
    var activeDevice: AndroidDevice? {
        devices.first { $0.isEmulator && $0.isReady }
            ?? devices.first { $0.isReady }
    }

    var hasReadyDevice: Bool { activeDevice != nil }

    // MARK: - Lifecycle

    func startPolling() {
        pollTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Refresh

    func refresh() async {
        await loadAvds()
        await loadDevices()
        updateStatusLine()
    }

    func loadAvds() async {
        guard let emulator else {
            avds = []
            return
        }
        let r = await Shell.run(emulator, ["-list-avds"], extraEnv: Toolchain.childEnvironment())
        let names = r.out
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("INFO") && !$0.hasPrefix("WARNING") }
        avds = names.map { Avd(name: $0, path: nil) }
    }

    func loadDevices() async {
        guard let adb else {
            devices = []
            return
        }
        let r = await Shell.run(adb, ["devices", "-l"], extraEnv: Toolchain.childEnvironment())
        var found: [AndroidDevice] = []
        for line in r.out.split(separator: "\n") {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty,
                  !text.hasPrefix("List of devices"),
                  !text.hasPrefix("*") else { continue }
            let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            let serial = parts[0]
            let state = parts[1]
            var model = ""
            var product = ""
            for p in parts.dropFirst(2) {
                if p.hasPrefix("model:") { model = String(p.dropFirst("model:".count)) }
                if p.hasPrefix("product:") { product = String(p.dropFirst("product:".count)) }
            }
            found.append(AndroidDevice(
                serial: serial,
                model: model,
                state: state,
                product: product,
                isEmulator: serial.hasPrefix("emulator-")
            ))
        }
        devices = found
    }

    private func updateStatusLine() {
        if let err = lastError, !err.isEmpty, devices.isEmpty {
            statusLine = err
            return
        }
        if isBooting {
            statusLine = "Booting…"
            return
        }
        if let d = activeDevice {
            statusLine = d.displayName
            return
        }
        if devices.isEmpty {
            statusLine = sdkAvailable ? "Emulator off" : "SDK not found"
        } else {
            statusLine = devices[0].state
        }
    }

    // MARK: - Boot

    /// Launches an AVD in the background and waits (without blocking the UI) for boot.
    func boot(avd: Avd) async {
        guard let emulator else {
            lastError = "Android emulator binary not found."
            return
        }
        guard !isBooting else { return }

        lastError = nil

        // Already running? Just make sure we are attached.
        if let d = devices.first(where: { $0.isEmulator && $0.isReady }) {
            statusLine = d.displayName
            return
        }

        let logURL = AppPaths.logsDirectory.appendingPathComponent("emulator-\(avd.name).log")

        var args: [String] = [
            "-avd", avd.name,
            "-netdelay", "none",
            "-netspeed", "full",
            "-no-boot-anim"
        ]
        if headless {
            args.append("-no-window")
        }

        guard let proc = Shell.launchDetached(
            emulator,
            args,
            cwd: Toolchain.androidSDK?.path,
            extraEnv: Toolchain.childEnvironment(),
            logTo: logURL
        ) else {
            lastError = "Could not launch the emulator process."
            return
        }

        launched[avd.name] = proc
        isBooting = true
        statusLine = "Booting \(avd.name)…"

        // Watch for boot completion off the main actor.
        let watchdog = Task { [weak self] in
            guard let self else { return }
            await self.awaitBoot(avd: avd, logURL: logURL)
        }
        bootWatchdogs[avd.name] = watchdog
    }

    private func awaitBoot(avd: Avd, logURL: URL) async {
        guard let adb else { return }
        let env = Toolchain.childEnvironment()
        let deadline = Date().addingTimeInterval(180)

        // 1. wait for a device to appear
        var serial: String?
        while Date() < deadline {
            if Task.isCancelled { return }
            await loadDevices()
            if let d = devices.first(where: { $0.isEmulator && $0.state == "device" }) {
                serial = d.serial
                break
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        guard let serial else {
            isBooting = false
            lastError = "Timed out waiting for the emulator to attach."
            statusLine = "Boot timed out"
            updateStatusLine()
            return
        }

        // 2. wait for the Android framework to finish booting
        while Date() < deadline {
            if Task.isCancelled { return }
            let r = await Shell.run(adb, ["-s", serial, "shell", "getprop", "sys.boot_completed"], extraEnv: env)
            if r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                isBooting = false
                updateStatusLine()
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        isBooting = false
        lastError = "Emulator attached but did not finish booting."
        updateStatusLine()
    }

    // MARK: - Stop

    /// Gracefully stops emulators via `adb emu kill`, then terminates our own processes.
    func stopAll() async {
        guard let adb else { return }
        let env = Toolchain.childEnvironment()
        let emulatorSerials = devices.filter { $0.isEmulator }.map { $0.serial }

        statusLine = "Stopping…"
        for serial in emulatorSerials {
            _ = await Shell.run(adb, ["-s", serial, "emu", "kill"], extraEnv: env)
        }

        for (_, task) in bootWatchdogs { task.cancel() }
        bootWatchdogs.removeAll()

        // Give the emulator a moment, then force-terminate anything still alive.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        for (name, proc) in launched where proc.isRunning {
            proc.terminate()
            launched[name] = nil
        }
        launched = launched.filter { $0.value.isRunning }

        isBooting = false
        await refresh()
        if devices.isEmpty { statusLine = "Emulator off" }
    }

    func stop(device: AndroidDevice) async {
        guard let adb, device.isEmulator else { return }
        _ = await Shell.run(adb, ["-s", device.serial, "emu", "kill"],
                            extraEnv: Toolchain.childEnvironment())
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await refresh()
    }

    // MARK: - Helpers

    func tailOfEmulatorLog(_ avdName: String, lines: Int = 12) -> String {
        let url = AppPaths.logsDirectory.appendingPathComponent("emulator-\(avdName).log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }
}
