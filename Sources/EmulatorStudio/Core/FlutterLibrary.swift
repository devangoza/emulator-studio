import Foundation
import Combine

/// Scans configured folders for Flutter projects and inspects their git branches.
@MainActor
final class FlutterLibrary: ObservableObject {

    @Published private(set) var projects: [FlutterProject] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published var roots: [String] {
        didSet { persistRoots(); Task { await scan() } }
    }

    private let rootsKey = "flutter.scanRoots"
    private let maxDepth = 4
    private let skipNames: Set<String> = [
        "build", ".dart_tool", ".git", "node_modules", "ios", "macos",
        "windows", "linux", "web", "Pods", ".idea", ".vscode", "gradle",
        ".gradle", "ephemeral", "DerivedData"
    ]

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: rootsKey) ?? []
        if stored.isEmpty {
            let home = NSHomeDirectory()
            var seeds: [String] = []
            for candidate in [
                "\(home)/StudioProjects",
                "\(home)/AndroidStudioProjects",
                "\(home)/Documents",
                "\(home)/Developer",
                "\(home)/Projects",
                "\(home)/Desktop/apps",
                "\(home)/Desktop",
                "\(home)/workbuddy-ai"
            ] {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                    seeds.append(candidate)
                }
            }
            roots = seeds
        } else {
            roots = stored
        }
    }

    private func persistRoots() {
        UserDefaults.standard.set(roots, forKey: rootsKey)
    }

    func addRoot(_ path: String) {
        let standardized = (path as NSString).expandingTildeInPath
        guard !roots.contains(standardized) else { return }
        roots.append(standardized)
    }

    func removeRoot(_ path: String) {
        roots.removeAll { $0 == path }
    }

    // MARK: - Scanning

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let rootList = roots
        let skip = skipNames
        let depth = maxDepth

        let found: [String] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [String] = []
                for root in rootList {
                    results += Self.walk(root: root, maxDepth: depth, skip: skip)
                }
                cont.resume(returning: Array(Set(results)).sorted())
            }
        }

        var built: [FlutterProject] = []
        for path in found {
            if let project = await Self.inspect(path: path) {
                built.append(project)
            }
        }

        projects = built.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lastScan = Date()
    }

    private static func walk(root: String, maxDepth: Int, skip: Set<String>) -> [String] {
        let fm = FileManager.default
        var hits: [String] = []
        var queue: [(String, Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (dir, level) = queue.removeFirst()
            guard level <= maxDepth else { continue }

            // Is this directory itself a Flutter project?
            let pubspec = (dir as NSString).appendingPathComponent("pubspec.yaml")
            if fm.fileExists(atPath: pubspec) {
                let android = (dir as NSString).appendingPathComponent("android")
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: android, isDirectory: &isDir), isDir.boolValue {
                    hits.append(dir)
                    continue   // don't descend into the project
                }
            }

            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries {
                if entry.hasPrefix(".") || skip.contains(entry) { continue }
                let child = (dir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
                queue.append((child, level + 1))
            }
        }
        return hits
    }

    // MARK: - Inspection

    static func inspect(path: String) async -> FlutterProject? {
        let fm = FileManager.default
        let env = Toolchain.childEnvironment()

        let pubspecPath = (path as NSString).appendingPathComponent("pubspec.yaml")
        let pubspecText = (try? String(contentsOfFile: pubspecPath, encoding: .utf8)) ?? ""

        // `name:` at column 0 in pubspec.yaml
        var packageName = (path as NSString).lastPathComponent
        for line in pubspecText.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("name:") {
                packageName = l.replacingOccurrences(of: "name:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                break
            }
        }

        // git — walk up, so a Flutter project nested inside a larger repo
        // (e.g. `monorepo/app`) still reports its branches.
        var isGit = false
        var repoRoot: String?
        var relativePath = ""
        var currentBranch: String?
        var branches: [String] = []

        let topLevel = await Shell.run(
            "/usr/bin/git",
            ["-C", path, "rev-parse", "--show-toplevel"],
            extraEnv: env
        )
        if topLevel.ok {
            let top = topLevel.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !top.isEmpty, fm.fileExists(atPath: top) {
                isGit = true
                repoRoot = top

                let rootURL = URL(fileURLWithPath: top).standardizedFileURL
                let projURL = URL(fileURLWithPath: path).standardizedFileURL
                if projURL.path != rootURL.path, projURL.path.hasPrefix(rootURL.path + "/") {
                    relativePath = String(projURL.path.dropFirst(rootURL.path.count + 1))
                }

                let head = await Shell.run(
                    "/usr/bin/git",
                    ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"],
                    extraEnv: env
                )
                if head.ok {
                    let b = head.out.trimmingCharacters(in: .whitespacesAndNewlines)
                    currentBranch = (b == "HEAD" || b.isEmpty) ? nil : b
                }
                branches = await listBranches(path: path, currentBranch: currentBranch)
            }
        }

        let applicationId = readApplicationId(projectPath: path)

        let attrs = try? fm.attributesOfItem(atPath: path)
        let modified = (attrs?[.modificationDate] as? Date) ?? .distantPast

        return FlutterProject(
            path: path,
            name: (path as NSString).lastPathComponent,
            packageName: packageName,
            applicationId: applicationId,
            isGit: isGit,
            repoRoot: repoRoot,
            relativePath: relativePath,
            currentBranch: currentBranch,
            branches: branches,
            lastModified: modified
        )
    }

    /// Local branches first, then remote-only branches. De-duplicated and pretty.
    static func listBranches(path: String, currentBranch: String?) async -> [String] {
        let env = Toolchain.childEnvironment()
        let r = await Shell.run(
            "/usr/bin/git",
            ["-C", path, "for-each-ref",
             "--format=%(refname)%09%(refname:short)",
             "refs/heads", "refs/remotes"],
            extraEnv: env
        )
        guard r.ok else { return [] }

        var locals: [String] = []
        var remotes: [String] = []

        for raw in r.out.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard !raw.isEmpty else { continue }
            let parts = raw.components(separatedBy: "\t")
            let full = parts.first ?? raw
            let short = parts.count > 1 ? parts[1] : raw

            // `refs/remotes/origin/HEAD` shortens to just `origin` — skip any HEAD alias.
            if full.hasSuffix("/HEAD") || short.hasSuffix("/HEAD") || short == "HEAD" { continue }

            if full.hasPrefix("refs/heads/") {
                if !short.isEmpty { locals.append(short) }
            } else if full.hasPrefix("refs/remotes/") {
                // Drop the remote name: `origin/feature` -> `feature`
                if let slash = short.firstIndex(of: "/") {
                    let name = String(short[short.index(after: slash)...])
                    if !name.isEmpty { remotes.append(name) }
                }
            }
        }

        var seen = Set<String>()
        var result: [String] = []

        // Current branch always first.
        if let currentBranch, !currentBranch.isEmpty {
            result.append(currentBranch)
            seen.insert(currentBranch)
        }

        for b in locals.sorted() where !seen.contains(b) {
            result.append(b)
            seen.insert(b)
        }

        for b in remotes.sorted() where !seen.contains(b) {
            result.append(b)
            seen.insert(b)
        }

        return result
    }

    /// Best-effort read of `applicationId` from the Android Gradle config.
    static func readApplicationId(projectPath: String) -> String? {
        let candidates = [
            "android/app/build.gradle.kts",
            "android/app/build.gradle"
        ]
        let pattern = #"applicationId\s*=?\s*["']([^"']+)["']"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        for rel in candidates {
            let full = (projectPath as NSString).appendingPathComponent(rel)
            guard let text = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
            let ns = text as NSString
            if let match = regex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1 {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    /// Re-read one project in place (after a branch switch outside the app).
    func refresh(project: FlutterProject) async {
        guard let updated = await Self.inspect(path: project.path) else { return }
        if let idx = projects.firstIndex(where: { $0.path == project.path }) {
            projects[idx] = updated
        }
    }
}
