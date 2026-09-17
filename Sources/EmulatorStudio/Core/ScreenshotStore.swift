import Foundation
import Combine
import AppKit

/// Captures emulator screenshots and keeps them organised per project.
@MainActor
final class ScreenshotStore: ObservableObject {

    @Published private(set) var shots: [Shot] = []
    @Published private(set) var groups: [String] = []
    @Published var selectedGroup: String = ScreenshotStore.allGroup
    @Published private(set) var isCapturing = false
    @Published private(set) var lastError: String?

    /// Project the screenshot button files into.
    @Published var targetGroup: String = ScreenshotStore.allGroup

    static let allGroup = "All"
    static let unsortedGroup = "Unsorted"

    private let rootKey = "screenshots.root"

    init() {
        if let stored = UserDefaults.standard.string(forKey: rootKey) {
            rootURL = URL(fileURLWithPath: stored)
        } else {
            rootURL = AppPaths.defaultScreenshotsDirectory
        }
    }

    @Published private(set) var rootURL: URL

    func setRoot(_ url: URL) {
        rootURL = url
        UserDefaults.standard.set(url.path, forKey: rootKey)
        Task { await reload() }
    }

    var filteredShots: [Shot] {
        if selectedGroup == Self.allGroup { return shots }
        return shots.filter { $0.group == selectedGroup }
    }

    // MARK: - Loading

    func reload() async {
        AppPaths.ensure(rootURL)
        let root = rootURL

        let result: ([Shot], [String]) = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                var collected: [Shot] = []

                guard let groupDirs = try? fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    cont.resume(returning: ([], []))
                    return
                }

                for dir in groupDirs {
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }

                    guard let files = try? fm.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for file in files where file.pathExtension.lowercased() == "png" {
                        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                        collected.append(Shot(
                            url: file,
                            group: dir.lastPathComponent,
                            createdAt: values?.contentModificationDate ?? .distantPast,
                            size: values?.fileSize ?? 0
                        ))
                    }
                }

                let names = Set(collected.map { $0.group }).sorted()
                cont.resume(returning: (collected.sorted { $0.createdAt > $1.createdAt }, names))
            }
        }

        shots = result.0
        groups = result.1
        if selectedGroup != Self.allGroup && !groups.contains(selectedGroup) {
            selectedGroup = Self.allGroup
        }
    }

    // MARK: - Capture

    @discardableResult
    func capture(serial: String, group: String) async -> Shot? {
        guard !isCapturing else { return nil }
        isCapturing = true
        lastError = nil
        defer { isCapturing = false }

        guard let adb = Toolchain.adbBinary else {
            lastError = "adb not found."
            return nil
        }

        let (code, data, errData) = await Shell.raw(
            adb.path,
            ["-s", serial, "exec-out", "screencap", "-p"],
            extraEnv: Toolchain.childEnvironment()
        )

        guard code == 0, data.count > 8 else {
            let msg = String(data: errData, encoding: .utf8) ?? "Unknown adb error"
            lastError = "Capture failed: \(msg.trimmingCharacters(in: .whitespacesAndNewlines))"
            return nil
        }

        // Sanity check: PNG magic bytes.
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        guard Array(data.prefix(4)) == pngMagic else {
            // Some adb builds prepend a CR; recover by scanning for the magic.
            if let range = data.range(of: Data(pngMagic)) {
                let recovered = data.subdata(in: range.lowerBound..<data.endIndex)
                return write(recovered, group: group)
            }
            lastError = "Device returned unexpected image data."
            return nil
        }

        return write(data, group: group)
    }

    private func write(_ data: Data, group: String) -> Shot? {
        let slug = AppPaths.slug(group.isEmpty ? Self.unsortedGroup : group)
        let dir = rootURL.appendingPathComponent(slug, isDirectory: true)
        AppPaths.ensure(dir)

        let now = Date()
        var name = "\(slug)-\(AppPaths.timestamp(now)).png"
        var url = dir.appendingPathComponent(name)

        // Avoid collisions when capturing twice in the same second.
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            name = "\(slug)-\(AppPaths.timestamp(now))-\(counter).png"
            url = dir.appendingPathComponent(name)
            counter += 1
        }

        do {
            try data.write(to: url)
        } catch {
            lastError = "Could not save screenshot: \(error.localizedDescription)"
            return nil
        }

        let shot = Shot(url: url, group: slug, createdAt: now, size: data.count)
        shots.insert(shot, at: 0)
        if !groups.contains(slug) {
            groups = (groups + [slug]).sorted()
        }
        return shot
    }

    // MARK: - Actions

    func delete(_ shot: Shot) {
        do {
            try FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
            shots.removeAll { $0.id == shot.id }
        } catch {
            // Fall back to a plain remove only if the trash is unavailable.
            try? FileManager.default.removeItem(at: shot.url)
            shots.removeAll { $0.id == shot.id }
        }
    }

    func reveal(_ shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    func open(_ shot: Shot) {
        NSWorkspace.shared.open(shot.url)
    }

    func copyToClipboard(_ shot: Shot) {
        guard let image = NSImage(contentsOf: shot.url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    func copyPath(_ shot: Shot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(shot.url.path, forType: .string)
    }

    func clearGroup(_ group: String) {
        let toRemove = shots.filter { $0.group == group }
        for shot in toRemove { delete(shot) }
    }

    /// Recent shots for a group — used by the drawer's preview strip.
    func recent(group: String, limit: Int = 12) -> [Shot] {
        let pool = group == Self.allGroup ? shots : shots.filter { $0.group == group }
        return Array(pool.prefix(limit))
    }
}
