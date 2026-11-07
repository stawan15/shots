import Foundation

/// Semantic version, compared numerically so 1.10.0 is newer than 1.9.0 (which a
/// string comparison gets wrong).
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Anything after the patch, e.g. the "b2" of "1.2.0-b2". Pre-releases sort
    /// before the matching release.
    public let prerelease: String?

    public init(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let withoutV = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed

        let (core, pre) = {
            guard let dash = withoutV.firstIndex(of: "-") else { return (withoutV, String?.none) }
            return (String(withoutV[withoutV.startIndex..<dash]),
                    String(withoutV[withoutV.index(after: dash)...]))
        }()

        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        func number(_ index: Int) -> Int {
            guard index < parts.count else { return 0 }
            // Take the leading digits so "2beta" still counts as 2.
            let digits = parts[index].prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
        self.major = number(0)
        self.minor = number(1)
        self.patch = number(2)
        self.prerelease = (pre?.isEmpty ?? true) ? nil : pre
    }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(base)-\($0)" } ?? base
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // A release outranks its own pre-releases: 1.2.0 > 1.2.0-b2.
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?): return left < right
        }
    }
}

/// The update check, shared by the app and the CLI.
public enum Updater {
    public static let repository = "stawan15/shots"
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases/latest")!

    public struct Release: Sendable {
        public let version: SemanticVersion
        public let tag: String
        public let name: String
        public let notes: String
        public let pageURL: URL
        public let assetURL: URL?
        public let assetSize: Int?
        /// "sha256:<hex>" as reported by the GitHub API, when present.
        public let digest: String?
    }

    public enum UpdateError: Error, CustomStringConvertible {
        case network(String)
        case badResponse(Int)
        case noRelease
        case checksumMismatch(expected: String, actual: String)
        case installFailed(String)

        public var description: String {
            switch self {
            case .network(let message): return "network error: \(message)"
            case .badResponse(let code): return "GitHub returned HTTP \(code)"
            case .noRelease: return "no release published yet"
            case .checksumMismatch(let expected, let actual):
                return "download checksum mismatch (expected \(expected), got \(actual))"
            case .installFailed(let message): return "could not install: \(message)"
            }
        }
    }

    /// Latest published release. Uses the unauthenticated API, which is fine for an
    /// occasional version check; a 404 means nothing has been released yet.
    public static func latestRelease(session: URLSession = .shared) async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Shots-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.network("unexpected response")
        }
        if http.statusCode == 404 { throw UpdateError.noRelease }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.badResponse(http.statusCode)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String
        else { throw UpdateError.network("unreadable release metadata") }

        let assets = object["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        let assetURL = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let assetSize = dmg?["size"] as? Int
        let digest = dmg?["digest"] as? String

        return Release(
            version: SemanticVersion(tag),
            tag: tag,
            name: object["name"] as? String ?? tag,
            notes: object["body"] as? String ?? "",
            pageURL: (object["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage,
            assetURL: assetURL,
            assetSize: assetSize,
            digest: digest)
    }

    /// Downloads the release DMG to a temporary file and verifies its digest.
    public static func download(
        _ release: Release,
        to directory: URL = FileManager.default.temporaryDirectory,
        session: URLSession = .shared,
        progress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        guard let assetURL = release.assetURL else {
            throw UpdateError.installFailed("this release has no DMG attached")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: assetURL)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.badResponse(http.statusCode)
        }
        progress?(1.0)

        // Verify before writing anything the installer might execute.
        if let digest = release.digest, digest.hasPrefix("sha256:") {
            let expected = String(digest.dropFirst("sha256:".count)).lowercased()
            var hasher = SHA256()
            hasher.update([UInt8](data))
            let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                throw UpdateError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        let destination = directory.appendingPathComponent("Shots-\(release.version).dmg")
        try? FileManager.default.removeItem(at: destination)
        try data.write(to: destination)
        return destination
    }

    /// Mounts the DMG, replaces the running bundle at `target`, and relaunches.
    ///
    /// Replacing a running app from inside itself is the awkward part of any
    /// self-updater; the copy-aside dance below keeps the new bundle intact even if
    /// the swap fails half way through.
    public static func install(
        dmg: URL,
        target: URL = Bundle.main.bundleURL,
        relaunch: Bool = true
    ) throws {
        let manager = FileManager.default
        let mountPoint = manager.temporaryDirectory
            .appendingPathComponent("shots-update-\(UUID().uuidString.prefix(8))")
        try manager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        defer { try? manager.removeItem(at: dmg) }

        var detach: () -> Void = {
            try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
        }
        defer { detach() }

        do {
            try runTool("/usr/bin/hdiutil", [
                "attach", dmg.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet",
            ])
        } catch {
            throw UpdateError.installFailed("could not open the downloaded dmg")
        }

        // Find the app inside the image rather than assuming its name.
        let contents = (try? manager.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)) ?? []
        guard let newBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.installFailed("the dmg does not contain an application")
        }

        let staging = manager.temporaryDirectory
            .appendingPathComponent("Shots-\(UUID().uuidString.prefix(8)).app")

        // Copy out of the read-only image to a writable location first: the code
        // signature must survive, so this has to be a real copy, not a move.
        do {
            try manager.copyItem(at: newBundle, to: staging)
        } catch {
            throw UpdateError.installFailed("could not copy the new version out of the dmg")
        }

        detach()
        detach = {}

        // Keep the old bundle until the new one is in place, so a failure leaves a
        // working app rather than nothing.
        let backup = manager.temporaryDirectory
            .appendingPathComponent("Shots-old-\(UUID().uuidString.prefix(8)).app")
        let wasRunning = manager.fileExists(atPath: target.path)

        do {
            if wasRunning { try manager.moveItem(at: target, to: backup) }
            try manager.moveItem(at: staging, to: target)
        } catch {
            // Roll back.
            if !manager.fileExists(atPath: target.path),
               manager.fileExists(atPath: backup.path) {
                try? manager.moveItem(at: backup, to: target)
            }
            throw UpdateError.installFailed(
                "could not replace the app at \(target.path). "
                + "If it is in /Applications, check that you have permission to write there.")
        }

        // Clear the quarantine flag the download picked up, or Gatekeeper will
        // refuse to launch the new build.
        try? runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
        // Re-sign ad-hoc: the original signature does not survive the new path.
        try? runTool("/usr/bin/codesign", ["--force", "--sign", "-", target.path])
        try? manager.removeItem(at: backup)

        if relaunch {
            relaunchApp(at: target)
        }
    }

    /// Opens the freshly installed app and quits the caller.
    public static func relaunchApp(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", url.path]
        try? process.run()
    }

    @discardableResult
    private static func runTool(_ path: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.installFailed("\(path) exited \(process.terminationStatus)")
        }
        return process.terminationStatus
    }

    /// UserDefaults key remembering when we last checked, so automatic checks do not
    /// hit the API on every launch.
    public static let lastCheckKey = "lastUpdateCheck"
    public static let automaticChecksKey = "automaticUpdateChecks"

    public static var automaticChecksEnabled: Bool {
        get {
            // Default to on: an updater nobody turns on is not an updater.
            if UserDefaults.standard.object(forKey: automaticChecksKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: automaticChecksKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: automaticChecksKey) }
    }

    /// True when an automatic check is due (at most once a day).
    public static func isCheckDue(interval: TimeInterval = 24 * 60 * 60) -> Bool {
        guard automaticChecksEnabled else { return false }
        guard let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else { return true }
        return Date().timeIntervalSince(last) >= interval
    }

    public static func markChecked() {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
    }
}
