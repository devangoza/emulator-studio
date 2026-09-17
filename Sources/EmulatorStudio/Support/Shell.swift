import Foundation

// MARK: - Shell result

struct ShellResult: Sendable {
    let code: Int32
    let out: String
    let err: String

    var ok: Bool { code == 0 }

    var combined: String {
        [out, err]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reference box so pipe readers can be filled from background queues safely.
private final class DataBox: @unchecked Sendable {
    var value = Data()
    private let lock = NSLock()
    func set(_ d: Data) { lock.lock(); value = d; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - Shell

enum Shell {

    /// Extra directories appended to PATH so `flutter`, `adb`, `git` etc. resolve
    /// even when the app is launched from Finder (which has a bare environment).
    static var augmentedPATH: String {
        let extra = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return ([current] + extra).filter { !$0.isEmpty }.joined(separator: ":")
    }

    private static func makeProcess(
        _ exe: String,
        _ args: [String],
        cwd: String?,
        extraEnv: [String: String]?
    ) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd, !cwd.isEmpty {
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH
        // Keep output clean and machine-parseable.
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["NO_COLOR"] = "1"
        env["CI"] = "1"
        if let extraEnv {
            for (k, v) in extraEnv { env[k] = v }
        }
        p.environment = env
        return p
    }

    /// Run a command and capture stdout/stderr as text.
    static func run(
        _ exe: String,
        _ args: [String] = [],
        cwd: String? = nil,
        extraEnv: [String: String]? = nil
    ) async -> ShellResult {
        let (code, outData, errData) = await raw(exe, args, cwd: cwd, extraEnv: extraEnv)
        return ShellResult(
            code: code,
            out: String(data: outData, encoding: .utf8) ?? "",
            err: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Run a command and capture raw bytes (used for `adb exec-out screencap -p`).
    static func raw(
        _ exe: String,
        _ args: [String] = [],
        cwd: String? = nil,
        extraEnv: [String: String]? = nil
    ) async -> (Int32, Data, Data) {
        await withCheckedContinuation { (cont: CheckedContinuation<(Int32, Data, Data), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = makeProcess(exe, args, cwd: cwd, extraEnv: extraEnv)
                let outPipe = Pipe()
                let errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                p.standardInput = FileHandle.nullDevice

                do {
                    try p.run()
                } catch {
                    cont.resume(returning: (-1, Data(), Data(error.localizedDescription.utf8)))
                    return
                }

                let outBox = DataBox()
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    outBox.set(outPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                p.waitUntilExit()
                group.wait()

                cont.resume(returning: (p.terminationStatus, outBox.get(), errBox.get()))
            }
        }
    }

    /// Run a long command and stream merged output line-by-line (for builds).
    static func stream(
        _ exe: String,
        _ args: [String] = [],
        cwd: String? = nil,
        extraEnv: [String: String]? = nil,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = makeProcess(exe, args, cwd: cwd, extraEnv: extraEnv)
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                p.standardInput = FileHandle.nullDevice

                let bufferBox = DataBox()
                bufferBox.set(Data())

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { return }
                    var buf = bufferBox.get()
                    buf.append(chunk)
                    while let nl = buf.firstIndex(of: 0x0A) {
                        let lineData = buf.subdata(in: buf.startIndex..<nl)
                        buf.removeSubrange(buf.startIndex...nl)
                        if let s = String(data: lineData, encoding: .utf8) {
                            let trimmed = s.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { onLine(trimmed) }
                        }
                    }
                    bufferBox.set(buf)
                }

                p.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let rest = bufferBox.get()
                    if !rest.isEmpty, let s = String(data: rest, encoding: .utf8) {
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { onLine(trimmed) }
                    }
                    cont.resume(returning: proc.terminationStatus)
                }

                do {
                    try p.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    onLine("failed to launch \(exe): \(error.localizedDescription)")
                    cont.resume(returning: -1)
                }
            }
        }
    }

    /// Launch a process that keeps running after we return (detached emulator).
    static func launchDetached(
        _ exe: String,
        _ args: [String] = [],
        cwd: String? = nil,
        extraEnv: [String: String]? = nil,
        logTo: URL? = nil
    ) -> Process? {
        let p = makeProcess(exe, args, cwd: cwd, extraEnv: extraEnv)

        if let logTo {
            FileManager.default.createFile(atPath: logTo.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: logTo) {
                p.standardOutput = handle
                p.standardError = handle
            }
        } else {
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }
        p.standardInput = FileHandle.nullDevice

        do {
            try p.run()
            return p
        } catch {
            return nil
        }
    }
}
