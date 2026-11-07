
import Foundation

// MARK: - Shared engine

/// Everything the CLI and the menu-bar app need, with no terminal or UI code.
public enum Shots {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tif", "tiff", "webp", "gif", "bmp", "pdf",
    ]

    /// macOS names screenshots "Screenshot 2026-11-06 at 13.45.38.png" (or Thai-era 2569).
    /// Only files that look like captures are touched unless `includeAll` is set, so a
    /// photo dropped on the Desktop is never moved by accident.
    public static func looksLikeScreenshot(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let prefixes = ["screenshot", "screen shot", "screencapture", "cleanshot", "snipaste", "capture"]
        return prefixes.contains { name.hasPrefix($0) }
    }

    /// The capture time macOS bakes into the filename. More trustworthy than the
    /// filesystem date, which is lost when a file is copied, and it survives the
    /// Thai Buddhist-era year (2569 -> 2026).
    public static func timestampInName(_ url: URL) -> Date? {
        let pattern = #"(\d{4})-(\d{2})-(\d{2})[ _]at[ _](\d{2})[.:](\d{2})[.:](\d{2})"#
        let name = url.lastPathComponent
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name))
        else { return nil }

        func group(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: name) else { return nil }
            return Int(name[range])
        }
        guard let year = group(1), let month = group(2), let day = group(3),
              let hour = group(4), let minute = group(5), let second = group(6)
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let gregorianYear = year > 2400 ? year - 543 : year
        return calendar.date(from: DateComponents(
            year: gregorianYear, month: month, day: day,
            hour: hour, minute: minute, second: second))
    }

    // MARK: Scanning

    public struct Scan {
        public var files: [URL]
        public var missing: [URL]
    }

    public static func scan(sources: [URL], destination: URL, includeAll: Bool) -> Scan {
        var files: [URL] = []
        var missing: [URL] = []

        for dir in sources {
            guard FileManager.default.fileExists(atPath: dir.path) else {
                missing.append(dir)
                continue
            }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            else { continue }

            for url in contents {
                let ext = url.pathExtension.lowercased()
                guard !ext.isEmpty, imageExtensions.contains(ext) else { continue }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                // Never re-file something already inside the destination tree.
                guard !url.path.hasPrefix(destination.path + "/") else { continue }
                guard includeAll || looksLikeScreenshot(url) else { continue }
                files.append(url)
            }
        }
        return Scan(files: files.sorted { $0.lastPathComponent < $1.lastPathComponent }, missing: missing)
    }

    // MARK: Planning

    public struct PlanItem: Identifiable {
        public var id: String { source.path }
        public let source: URL
        public var destination: URL
        public let folder: String
        public let stem: String
        public let date: Date
        public let width: Int
        public let height: Int
        /// A couple of OCR lines, for previewing why a name was chosen.
        public let preview: String

        public var originalName: String { source.lastPathComponent }
        public var newName: String { destination.lastPathComponent }
    }

    public struct Plan {
        public var items: [PlanItem] = []
        public var duplicates: [URL] = []
        public var skipped: [URL] = []

        public init(items: [PlanItem] = [], duplicates: [URL] = [], skipped: [URL] = []) {
            self.items = items
            self.duplicates = duplicates
            self.skipped = skipped
        }

        public var isEmpty: Bool { items.isEmpty }
    }

    public static func destinationURL(
        name: Namer.Name, extension ext: String, date: Date, root: URL, layout: String
    ) -> URL {
        // Force the Gregorian calendar: with a Thai locale the default is Buddhist.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
        let time = String(format: "%02d%02d", parts.hour ?? 0, parts.minute ?? 0)
        let filename = "\(day)-\(time)-\(name.stem).\(ext)"

        let base: URL
        switch layout {
        case "topic": base = root.appendingPathComponent(name.folder)
        case "both": base = root.appendingPathComponent(name.folder).appendingPathComponent(day)
        default: base = root.appendingPathComponent(day)
        }
        return base.appendingPathComponent(filename)
    }

    /// Never overwrite: bump to `name-2.ext`, `name-3.ext`, ... Also treats paths
    /// already claimed earlier in this run as taken, since two screenshots can
    /// legitimately want the same name before either exists on disk.
    public static func unique(_ url: URL, reserved: Set<String> = []) -> URL {
        let manager = FileManager.default
        let taken = { (candidate: URL) in
            manager.fileExists(atPath: candidate.path) || reserved.contains(candidate.path)
        }
        guard taken(url) else { return url }
        let base = url.deletingPathExtension()
        let ext = url.pathExtension
        var counter = 2
        while true {
            let candidate = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent)-\(counter).\(ext)")
            if !taken(candidate) { return candidate }
            counter += 1
        }
    }

    /// SHA-256 of the file bytes, used to spot shots you captured twice.
    /// Implemented locally rather than with CryptoKit so the engine builds and its
    /// checks run on Linux CI as well as macOS.
    public static func contentHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update([UInt8](chunk))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func plan(
        files: [URL],
        destination: URL,
        layout: String,
        rules: [Rule],
        languages: [String],
        progress: ((Int, Int) -> Void)? = nil
    ) -> Plan {
        guard !files.isEmpty else { return Plan() }

        let analyzed = analyzeAll(files, languages: languages, progress: progress)

        var plan = Plan()
        var reserved = Set<String>()
        var seenHashes: [String: URL] = [:]

        for (url, result) in analyzed {
            guard case .success(let facts) = result else {
                plan.skipped.append(url)
                continue
            }

            if let hash = contentHash(url) {
                if seenHashes[hash] != nil {
                    plan.duplicates.append(url)
                    continue
                }
                seenHashes[hash] = url
            }

            let isCapture = looksLikeScreenshot(url)
            let date = timestampInName(url) ?? facts.creationDate
            guard var name = Namer.name(for: facts, extra: rules, isCapture: isCapture) else {
                plan.skipped.append(url)
                continue
            }
            let ext = url.pathExtension.lowercased()
            var target = destinationURL(name: name, extension: ext, date: date, root: destination, layout: layout)

            // Prefer a different title over "-2" when two shots collide.
            var attempt = 1
            while reserved.contains(target.path) || FileManager.default.fileExists(atPath: target.path) {
                guard attempt < 6,
                      let candidate = Namer.name(for: facts, extra: rules, isCapture: isCapture, attempt: attempt)
                else { break }
                name = candidate
                target = destinationURL(name: name, extension: ext, date: date, root: destination, layout: layout)
                attempt += 1
            }
            if reserved.contains(target.path) || FileManager.default.fileExists(atPath: target.path) {
                target = unique(target, reserved: reserved)
            }
            reserved.insert(target.path)

            plan.items.append(PlanItem(
                source: url,
                destination: target,
                folder: name.folder,
                stem: name.stem,
                date: date,
                width: facts.width,
                height: facts.height,
                preview: facts.lines.prefix(4).joined(separator: " · ")))
        }
        return plan
    }

    // MARK: Applying

    /// Moves the items and writes an undo journal. Returns the moves that succeeded.
    @discardableResult
    public static func apply(_ items: [PlanItem], destinationRoot: String) throws -> [Move] {
        var moves: [Move] = []
        for item in items {
            try FileManager.default.createDirectory(
                at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let final = unique(item.destination)
            try FileManager.default.moveItem(at: item.source, to: final)
            moves.append(Move(from: item.source.path, to: final.path))
        }
        if !moves.isEmpty {
            try Journal.write(JournalEntry(date: Date(), destination: destinationRoot, moves: moves))
        }
        return moves
    }

    /// Creates a tiny placeholder file used by tests to simulate a capture.
    public static func touch(_ url: URL, contents: Data = Data()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
    }
}

// MARK: - Journal

public struct Move: Codable, Sendable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public struct JournalEntry: Codable, Sendable {
    public let date: Date
    public let destination: String
    public let moves: [Move]

    public init(date: Date, destination: String, moves: [Move]) {
        self.date = date
        self.destination = destination
        self.moves = moves
    }
}

public enum Journal {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/shots")
    }

    public static func write(_ entry: JournalEntry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("journal-\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: url)
    }

    /// Newest journal first.
    public static func entries() -> [(url: URL, entry: JournalEntry)] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.lastPathComponent.hasPrefix("journal-") && $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? decoder.decode(JournalEntry.self, from: data)
                else { return nil }
                return (url, entry)
            }
            .sorted { $0.entry.date > $1.entry.date }
    }

    public struct UndoResult {
        public let restored: Int
        public let skipped: Int
        public let date: Date
    }

    /// Puts the most recent batch back where it came from, preserving names.
    public static func undoLast() -> UndoResult? {
        guard let (url, entry) = entries().first else { return nil }
        var restored = 0
        var skipped = 0
        for move in entry.moves {
            let from = URL(fileURLWithPath: move.to)
            let to = URL(fileURLWithPath: move.from)
            guard FileManager.default.fileExists(atPath: from.path) else {
                skipped += 1
                continue
            }
            let target = Shots.unique(to)
            do {
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: from, to: target)
                restored += 1
            } catch {
                skipped += 1
            }
        }
        try? FileManager.default.removeItem(at: url)
        return UndoResult(restored: restored, skipped: skipped, date: entry.date)
    }
}
