import Foundation

/// Locates the external tools this app drives: Android SDK (adb + emulator) and Flutter.
/// Everything is cached; call `Toolchain.invalidate()` after the user changes paths.
enum Toolchain {

    // MARK: - Android SDK

    private static var cachedSDK: URL??
    private static var cachedFlutter: URL??

    static func invalidate() {
        cachedSDK = nil
        cachedFlutter = nil
    }

    static var androidSDK: URL? {
        if let cachedSDK { return cachedSDK }
        let found = locateAndroidSDK()
        cachedSDK = found
        return found
    }

    private static func locateAndroidSDK() -> URL? {
        let env = ProcessInfo.processInfo.environment
        var candidates: [String] = []

        if let v = env["ANDROID_SDK_ROOT"], !v.isEmpty { candidates.append(v) }
        if let v = env["ANDROID_HOME"], !v.isEmpty { candidates.append(v) }
        if let v = env["ANDROID_SDK"], !v.isEmpty { candidates.append(v) }

        let home = NSHomeDirectory()
        candidates += [
            "\(home)/Library/Android/sdk",
            "\(home)/Android/sdk",
            "\(home)/Android/Sdk",
            "/usr/local/share/android-sdk",
            "/opt/homebrew/share/android-sdk",
            "/opt/android-sdk"
        ]

        // Derive from a `flutter` install if one is configured.
        if let f = flutterBinary {
            // <flutter>/bin/flutter  ->  we just probe the standard env file
            let envFile = f.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("packages/flutter_tools/gradle")
            if FileManager.default.fileExists(atPath: envFile.path) {
                // nothing extra; kept for future use
            }
        }

        for c in candidates {
            let url = URL(fileURLWithPath: (c as NSString).expandingTildeInPath)
            if isValidSDK(url) { return url }
        }

        // Last resort: ask the login shell where `adb` lives and walk upwards.
        if let adbPath = whichViaLoginShell("adb") {
            let url = URL(fileURLWithPath: adbPath)
                .deletingLastPathComponent()   // platform-tools
                .deletingLastPathComponent()   // sdk root
            if isValidSDK(url) { return url }
        }

        return nil
    }

    private static func isValidSDK(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("platform-tools/adb").path)
            || fm.fileExists(atPath: url.appendingPathComponent("emulator/emulator").path)
    }

    static var adbBinary: URL? {
        guard let sdk = androidSDK else { return nil }
        let url = sdk.appendingPathComponent("platform-tools/adb")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var emulatorBinary: URL? {
        guard let sdk = androidSDK else { return nil }
        let url = sdk.appendingPathComponent("emulator/emulator")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var sdkRootPath: String? { androidSDK?.path }

    // MARK: - Flutter

    static var flutterBinary: URL? {
        if let cachedFlutter { return cachedFlutter }
        let found = locateFlutter()
        cachedFlutter = found
        return found
    }

    private static func locateFlutter() -> URL? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        var candidates: [String] = []

        if let v = env["FLUTTER_ROOT"], !v.isEmpty {
            candidates.append("\(v)/bin/flutter")
        }

        let home = NSHomeDirectory()
        candidates += [
            "\(home)/Downloads/flutter/bin/flutter",
            "\(home)/development/flutter/bin/flutter",
            "\(home)/flutter/bin/flutter",
            "\(home)/fvm/default/bin/flutter",
            "\(home)/.puro/shared/flutter/bin/flutter",
            "/opt/homebrew/bin/flutter",
            "/usr/local/bin/flutter",
            "/opt/flutter/bin/flutter"
        ]

        // fvm-managed versions
        let fvmVersions = "\(home)/fvm/versions"
        if let versions = try? fm.contentsOfDirectory(atPath: fvmVersions) {
            for v in versions.sorted().reversed() {
                candidates.append("\(fvmVersions)/\(v)/bin/flutter")
            }
        }

        for c in candidates {
            let url = URL(fileURLWithPath: (c as NSString).expandingTildeInPath)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }

        if let p = whichViaLoginShell("flutter") {
            let url = URL(fileURLWithPath: p)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }

        return nil
    }

    static var flutterRootPath: String? {
        guard let f = flutterBinary else { return nil }
        // <root>/bin/flutter
        return f.deletingLastPathComponent().deletingLastPathComponent().path
    }

    // MARK: - Login shell lookup

    /// Finder-launched apps inherit a minimal PATH; ask the user's login shell.
    static func whichViaLoginShell(_ tool: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "/usr/bin/env \(tool)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let out = (String(data: data, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("/") }
        return out
    }

    // MARK: - Environment for child processes

    static func childEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        if let sdk = sdkRootPath {
            env["ANDROID_SDK_ROOT"] = sdk
            env["ANDROID_HOME"] = sdk
        }
        if let root = flutterRootPath {
            env["FLUTTER_ROOT"] = root
        }
        return env
    }
}
