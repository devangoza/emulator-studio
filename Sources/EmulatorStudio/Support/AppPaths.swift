import Foundation

enum AppPaths {

    static let fm = FileManager.default

    /// ~/Library/Application Support/EmulatorStudio
    static var supportDirectory: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("EmulatorStudio", isDirectory: true)
        ensure(dir)
        return dir
    }

    static var logsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("logs", isDirectory: true)
        ensure(dir)
        return dir
    }

    /// Where `git worktree` checkouts for non-current branches live.
    static var worktreesDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("worktrees", isDirectory: true)
        ensure(dir)
        return dir
    }

    /// Default screenshot library: ~/Pictures/EmulatorStudio
    static var defaultScreenshotsDirectory: URL {
        let base = fm.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        return base.appendingPathComponent("EmulatorStudio", isDirectory: true)
    }

    static func ensure(_ url: URL) {
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Turn an arbitrary project name into a safe folder name.
    static func slug(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let s = String(mapped)
        let collapsed = s.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? "unsorted" : String(trimmed.prefix(60))
    }

    static func timestamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: date)
    }
}
