import Foundation

// MARK: - Android device

struct AndroidDevice: Identifiable, Hashable {
    let serial: String
    let model: String
    let state: String          // device | offline | unauthorized | booting
    let product: String
    let isEmulator: Bool

    var id: String { serial }

    var displayName: String {
        if model.isEmpty { return serial }
        let cleaned = model.replacingOccurrences(of: "_", with: " ")
        return isEmulator ? "\(cleaned)" : "\(cleaned) · \(serial)"
    }

    var isReady: Bool { state == "device" }
    var isBooting: Bool { state == "offline" || state == "booting" }
}

// MARK: - Flutter project

struct FlutterProject: Identifiable, Hashable {
    let path: String
    let name: String              // folder name
    let packageName: String       // from pubspec.yaml `name:`
    let applicationId: String?    // android applicationId
    let isGit: Bool
    let repoRoot: String?         // toplevel of the enclosing git repo, if any
    let relativePath: String      // this project's path relative to repoRoot ("" when it is the root)
    let currentBranch: String?
    let branches: [String]
    let lastModified: Date

    var id: String { path }

    /// A label that disambiguates projects nested inside a larger repo,
    /// e.g. `new kundli/app` instead of a bare `app`.
    var displayName: String {
        if let repoRoot, !relativePath.isEmpty {
            let repoName = (repoRoot as NSString).lastPathComponent
            return "\(repoName)/\(relativePath)"
        }
        return name
    }

    var displayBranch: String {
        guard let currentBranch, !currentBranch.isEmpty else { return "no git" }
        return currentBranch
    }

    var hasBranches: Bool { branches.count > 0 }

    /// True when the Flutter project sits inside a larger repository
    /// (e.g. `monorepo/app`). Branch builds then happen in a subfolder of the worktree.
    var isNestedInRepo: Bool { isGit && !relativePath.isEmpty }

    /// Remote-tracking names get a nicer label.
    static func prettyBranch(_ raw: String) -> String {
        raw.replacingOccurrences(of: "^origin/", with: "", options: .regularExpression)
    }
}

// MARK: - Build variant

enum BuildVariant: String, CaseIterable, Identifiable {
    case debug
    case profile
    case release

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var flutterArgs: [String] {
        switch self {
        case .debug:   return ["--debug"]
        case .profile: return ["--profile"]
        case .release: return ["--release"]
        }
    }

    var apkFileName: String {
        switch self {
        case .debug:   return "app-debug.apk"
        case .profile: return "app-profile.apk"
        case .release: return "app-release.apk"
        }
    }
}

// MARK: - Install job

enum InstallStage: Equatable {
    case idle
    case preparingWorkspace
    case building
    case installing
    case launching
    case done
    case failed(String)

    var title: String {
        switch self {
        case .idle:               return "Idle"
        case .preparingWorkspace: return "Preparing branch workspace"
        case .building:           return "Building APK"
        case .installing:         return "Installing on device"
        case .launching:          return "Launching app"
        case .done:               return "Installed"
        case .failed:             return "Failed"
        }
    }

    var isBusy: Bool {
        switch self {
        case .preparingWorkspace, .building, .installing, .launching: return true
        default: return false
        }
    }
}

struct InstallJob: Identifiable, Equatable {
    let id = UUID()
    let projectPath: String
    let projectName: String
    let branch: String
    let variant: BuildVariant
    let deviceSerial: String
    var stage: InstallStage = .idle
    var log: [String] = []

    static func == (lhs: InstallJob, rhs: InstallJob) -> Bool { lhs.id == rhs.id }
}

// MARK: - Screenshot

struct Shot: Identifiable, Hashable {
    let url: URL
    let group: String
    let createdAt: Date
    let size: Int

    var id: String { url.path }
    var fileName: String { url.lastPathComponent }
}

// MARK: - AVD

struct Avd: Identifiable, Hashable {
    let name: String
    let path: String?
    var id: String { name }
}
