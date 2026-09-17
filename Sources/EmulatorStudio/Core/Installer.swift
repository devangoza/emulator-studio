import Foundation
import Combine

/// Builds a Flutter project from a chosen git branch and installs it on a device.
///
/// Branch safety: we never `git checkout` inside the user's working copy.
/// A throwaway `git worktree` is created in Application Support for the target
/// branch, built there, and removed afterwards. The user's repo is untouched.
@MainActor
final class Installer: ObservableObject {

    @Published private(set) var jobs: [InstallJob] = []

    private var running: [UUID: Task<Void, Never>] = [:]

    var activeJob: InstallJob? {
        jobs.last { $0.stage.isBusy }
    }

    var isBusy: Bool { activeJob != nil }

    // MARK: - Public entry point

    func install(
        project: FlutterProject,
        branch: String,
        variant: BuildVariant,
        device: AndroidDevice,
        reuseExistingBuild: Bool = false
    ) {
        guard !isBusy else { return }

        var job = InstallJob(
            projectPath: project.path,
            projectName: project.displayName,
            branch: branch,
            variant: variant,
            deviceSerial: device.serial
        )
        job.stage = .preparingWorkspace
        job.log = ["▶ \(project.displayName) · \(branch) · \(variant.title) → \(device.serial)"]
        jobs.append(job)

        let jobID = job.id
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(jobID: jobID, project: project, reuseExistingBuild: reuseExistingBuild)
        }
        running[jobID] = task
    }

    func clearFinished() {
        jobs.removeAll { !$0.stage.isBusy }
    }

    // MARK: - Pipeline

    private func run(jobID: UUID, project: FlutterProject, reuseExistingBuild: Bool) async {
        let env = Toolchain.childEnvironment()

        guard let flutter = Toolchain.flutterBinary else {
            fail(jobID, "Flutter SDK not found. Install Flutter or add it to PATH.")
            return
        }
        guard let adb = Toolchain.adbBinary else {
            fail(jobID, "adb not found. Android SDK platform-tools is missing.")
            return
        }

        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let branch = job.branch
        let variant = job.variant
        let serial = job.deviceSerial

        // ---- 1. Decide where to build -------------------------------------
        let needsWorktree = project.isGit
            && !branch.isEmpty
            && branch != project.currentBranch

        var buildDir = project.path
        var worktreePath: String?

        if needsWorktree {
            append(jobID, "Creating isolated workspace for branch '\(branch)'…")
            guard let wt = await prepareWorktree(project: project, branch: branch, jobID: jobID) else {
                return   // prepareWorktree already reported the failure
            }
            worktreePath = wt
            // A worktree checks out the whole repository; if this Flutter project
            // lives in a subfolder (monorepo layout) we must build from there.
            if project.relativePath.isEmpty {
                buildDir = wt
            } else {
                buildDir = (wt as NSString).appendingPathComponent(project.relativePath)
                append(jobID, "Project lives at \(project.relativePath)/ inside the repo.")
            }
        } else {
            append(jobID, project.isGit
                   ? "Building current branch '\(project.currentBranch ?? "-")' in place."
                   : "Not a git repo — building in place.")
        }

        // ---- 2. Build -----------------------------------------------------
        var apkPath = (buildDir as NSString)
            .appendingPathComponent("build/app/outputs/flutter-apk/\(variant.apkFileName)")

        let apkExists = FileManager.default.fileExists(atPath: apkPath)
        let skipBuild = reuseExistingBuild && apkExists

        if skipBuild {
            append(jobID, "Reusing existing build: \(apkPath)")
            setStage(jobID, .installing)
        } else {
            setStage(jobID, .building)
            append(jobID, "$ flutter build apk \(variant.flutterArgs.joined(separator: " "))")

            var args = ["build", "apk"] + variant.flutterArgs
            if variant == .release {
                args.append("--no-shrink")
            }

            var buildEnv = env
            buildEnv["PATH"] = "\((flutter.deletingLastPathComponent().path)):\(Shell.augmentedPATH)"

            let code = await Shell.stream(
                flutter.path,
                args,
                cwd: buildDir,
                extraEnv: buildEnv
            ) { [weak self] line in
                Task { @MainActor in self?.append(jobID, line) }
            }

            guard code == 0 else {
                fail(jobID, "flutter build failed (exit \(code)). See log above.")
                await cleanupWorktree(project: project, path: worktreePath, jobID: jobID)
                return
            }

            // Flutter sometimes emits a differently-cased name; fall back to a search.
            if !FileManager.default.fileExists(atPath: apkPath) {
                if let found = Self.findApk(buildDir: buildDir, variant: variant) {
                    apkPath = found
                } else {
                    fail(jobID, "Build succeeded but no APK was found.")
                    await cleanupWorktree(project: project, path: worktreePath, jobID: jobID)
                    return
                }
            }

            setStage(jobID, .installing)
            append(jobID, "APK ready: \((apkPath as NSString).lastPathComponent)")
        }

        // ---- 3. Install ---------------------------------------------------
        let installResult = await Shell.run(
            adb.path,
            ["-s", serial, "install", "-r", "-d", apkPath],
            extraEnv: env
        )
        let installOut = installResult.combined
        if !installOut.isEmpty { append(jobID, installOut) }

        if !installResult.ok || installOut.contains("Failure") {
            // Signature mismatch or a stale package: uninstall and retry once.
            if let appId = project.applicationId {
                append(jobID, "Retrying after uninstalling \(appId)…")
                _ = await Shell.run(adb.path, ["-s", serial, "uninstall", appId], extraEnv: env)
                let retry = await Shell.run(adb.path, ["-s", serial, "install", "-r", apkPath], extraEnv: env)
                if !retry.combined.isEmpty { append(jobID, retry.combined) }
                if !retry.ok {
                    fail(jobID, "Install failed.")
                    await cleanupWorktree(project: project, path: worktreePath, jobID: jobID)
                    return
                }
            } else {
                fail(jobID, "Install failed.")
                await cleanupWorktree(project: project, path: worktreePath, jobID: jobID)
                return
            }
        }

        // ---- 4. Launch ----------------------------------------------------
        setStage(jobID, .launching)
        if let appId = project.applicationId {
            let launch = await Shell.run(
                adb.path,
                ["-s", serial, "shell", "monkey", "-p", appId, "-c", "android.intent.category.LAUNCHER", "1"],
                extraEnv: env
            )
            append(jobID, "Launched \(appId)")
            _ = launch
        } else {
            append(jobID, "No applicationId found — install only.")
        }

        setStage(jobID, .done)
        append(jobID, "✓ Done.")

        await cleanupWorktree(project: project, path: worktreePath, jobID: jobID)
        running[jobID] = nil
    }

    // MARK: - Worktree handling

    private func prepareWorktree(project: FlutterProject, branch: String, jobID: UUID) async -> String? {
        let env = Toolchain.childEnvironment()
        let slug = AppPaths.slug("\(project.name)-\(branch)")
        let path = AppPaths.worktreesDirectory.appendingPathComponent(slug, isDirectory: true).path

        // Reuse a previous checkout if it is still registered.
        if FileManager.default.fileExists(atPath: path) {
            append(jobID, "Removing previous workspace…")
            _ = await Shell.run("/usr/bin/git", ["-C", project.path, "worktree", "remove", "--force", path], extraEnv: env)
            _ = await Shell.run("/usr/bin/git", ["-C", project.path, "worktree", "prune"], extraEnv: env)
            try? FileManager.default.removeItem(atPath: path)
        }

        // Resolve the ref: local first, then origin/<branch>.
        let candidates = [branch, "origin/\(branch)", "refs/remotes/origin/\(branch)"]

        for ref in candidates {
            let r = await Shell.run(
                "/usr/bin/git",
                ["-C", project.path, "worktree", "add", "--detach", "--force", path, ref],
                extraEnv: env
            )
            if r.ok {
                append(jobID, "Workspace ready at \(path) (\(ref))")
                return path
            }
            // Clean up a half-created directory before trying the next ref.
            try? FileManager.default.removeItem(atPath: path)
        }

        fail(jobID, "Could not create a workspace for branch '\(branch)'. Is the branch fetched?")
        return nil
    }

    private func cleanupWorktree(project: FlutterProject, path: String?, jobID: UUID) async {
        guard let path else { return }
        let env = Toolchain.childEnvironment()
        _ = await Shell.run("/usr/bin/git", ["-C", project.path, "worktree", "remove", "--force", path], extraEnv: env)
        _ = await Shell.run("/usr/bin/git", ["-C", project.path, "worktree", "prune"], extraEnv: env)
    }

    // MARK: - Helpers

    private static func findApk(buildDir: String, variant: BuildVariant) -> String? {
        let dir = (buildDir as NSString).appendingPathComponent("build/app/outputs/flutter-apk")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        let matches = entries.filter { $0.hasSuffix(".apk") }
        // Prefer the variant we asked for.
        if let exact = matches.first(where: { $0 == variant.apkFileName }) {
            return (dir as NSString).appendingPathComponent(exact)
        }
        if let loose = matches.first(where: { $0.contains(variant.rawValue) }) {
            return (dir as NSString).appendingPathComponent(loose)
        }
        return matches.first.map { (dir as NSString).appendingPathComponent($0) }
    }

    /// Does a previous build exist for this project + variant?
    static func existingApk(project: FlutterProject, variant: BuildVariant) -> String? {
        let dir = (project.path as NSString).appendingPathComponent("build/app/outputs/flutter-apk")
        let exact = (dir as NSString).appendingPathComponent(variant.apkFileName)
        return FileManager.default.fileExists(atPath: exact) ? exact : nil
    }

    private func append(_ jobID: UUID, _ line: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].log.append(line)
        if jobs[idx].log.count > 600 {
            jobs[idx].log.removeFirst(jobs[idx].log.count - 600)
        }
    }

    private func setStage(_ jobID: UUID, _ stage: InstallStage) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].stage = stage
    }

    private func fail(_ jobID: UUID, _ message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].stage = .failed(message)
        jobs[idx].log.append("✗ \(message)")
        running[jobID] = nil
    }
}
