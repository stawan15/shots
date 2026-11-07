import CryptoKit
import Foundation
import ShotsCore

// MARK: - Small terminal helpers

let isTTY = isatty(STDOUT_FILENO) == 1
func dim(_ s: String) -> String { isTTY ? "\u{001B}[2m\(s)\u{001B}[0m" : s }
func bold(_ s: String) -> String { isTTY ? "\u{001B}[1m\(s)\u{001B}[0m" : s }
func green(_ s: String) -> String { isTTY ? "\u{001B}[32m\(s)\u{001B}[0m" : s }
func yellow(_ s: String) -> String { isTTY ? "\u{001B}[33m\(s)\u{001B}[0m" : s }
func red(_ s: String) -> String { isTTY ? "\u{001B}[31m\(s)\u{001B}[0m" : s }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((red("error: ") + message + "\n").utf8))
    exit(1)
}

let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp", "gif", "bmp", "pdf"]

/// macOS names screenshots "Screenshot 2026-11-06 at 13.45.38.png" (or Thai-era 2569).
/// We only touch files that look like captures unless `--all` is passed, so a photo
/// dropped on the Desktop is never moved by accident.
func looksLikeScreenshot(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    let prefixes = ["screenshot", "screen shot", "screencapture", "cleanshot", "snipaste", "capture"]
    return prefixes.contains { name.hasPrefix($0) }
}

// MARK: - Journal

struct Move: Codable {
    let from: String
    let to: String
}

struct JournalEntry: Codable {
    let date: Date
    let destination: String
    let moves: [Move]
}

enum Journal {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/shots")
    }

    static func write(_ entry: JournalEntry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("journal-\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: url)
    }

    /// Newest journal first.
    static func entries() -> [(URL, JournalEntry)] {
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
            .sorted { $0.1.date > $1.1.date }
    }
}

// MARK: - Plan

/// SHA-256 of the file bytes, used to spot shots you captured twice.
func contentHash(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

struct Action {
    let source: URL
    let destination: URL
    let facts: ImageFacts
    let name: Namer.Name
    /// Capture time, taken from the filename when available.
    let date: Date
}

struct Options {
    var sources: [URL] = []
    var destination: URL?
    var layout: String?
    var yes = false
    var all = false
    var json = false
    var quiet = false
    var interval: TimeInterval = 30
}

func parse(_ arguments: [String]) -> (command: String, options: Options) {
    var options = Options()
    var positional: [String] = []
    var index = 0
    let args = arguments

    func value() -> String {
        index += 1
        guard index < args.count else { fail("missing value for \(args[index - 1])") }
        return args[index]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--dir", "-d":
            options.sources.append(URL(fileURLWithPath: (value() as NSString).expandingTildeInPath))
        case "--to":
            options.destination = URL(fileURLWithPath: (value() as NSString).expandingTildeInPath)
        case "--layout":
            let mode = value()
            guard ["day", "topic", "both"].contains(mode) else {
                fail("--layout expects day, topic or both")
            }
            options.layout = mode
        case "--yes", "-y":
            options.yes = true
        case "--all":
            options.all = true
        case "--json":
            options.json = true
        case "--quiet", "-q":
            options.quiet = true
        case "--interval":
            options.interval = max(5, TimeInterval(value()) ?? 30)
        case "--help", "-h":
            positional.append("help")
        default:
            if arg.hasPrefix("-") { fail("unknown flag \(arg)") }
            positional.append(arg)
        }
        index += 1
    }

    return (positional.first ?? "help", options)
}

func collect(_ options: Options, config: Config) -> [URL] {
    let dirs = options.sources.isEmpty
        ? config.sources.map { URL(fileURLWithPath: $0) }
        : options.sources
    let destination = options.destination ?? URL(fileURLWithPath: config.destination)

    var found: [URL] = []
    for dir in dirs {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { continue }

        for url in contents where url.pathExtension.lowercased() != "" {
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard !url.path.hasPrefix(destination.path + "/") else { continue }
            guard options.all || looksLikeScreenshot(url) else { continue }
            found.append(url)
        }
    }
    return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// The capture time macOS bakes into the filename ("Screenshot 2026-11-06 at 13.45.38.png").
/// More trustworthy than the filesystem date, which is lost when a file is copied,
/// and it survives the Thai Buddhist-era year (2569 -> 2026).
func timestampInName(_ url: URL) -> Date? {
    let pattern = #"(\d{4})-(\d{2})-(\d{2})[ _]at[ _](\d{2})[.:](\d{2})[.:](\d{2})"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(
            in: url.lastPathComponent,
            options: [],
            range: NSRange(url.lastPathComponent.startIndex..., in: url.lastPathComponent))
    else { return nil }

    func group(_ index: Int) -> Int? {
        guard let range = Range(match.range(at: index), in: url.lastPathComponent) else { return nil }
        return Int(url.lastPathComponent[range])
    }
    guard let year = group(1), let month = group(2), let day = group(3),
          let hour = group(4), let minute = group(5), let second = group(6)
    else { return nil }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    // macOS writes the year in the system calendar, so a Thai user gets 2569.
    let gregorianYear = year > 2400 ? year - 543 : year
    return calendar.date(from: DateComponents(
        year: gregorianYear, month: month, day: day,
        hour: hour, minute: minute, second: second))
}

func destinationURL(for facts: ImageFacts, name: Namer.Name, root: URL, layout: String, date: Date) -> URL {
    // Force the Gregorian calendar: with a Thai locale the default is Buddhist.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let day = String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    let time = String(format: "%02d%02d", parts.hour ?? 0, parts.minute ?? 0)
    let filename = "\(day)-\(time)-\(name.stem).\(facts.url.pathExtension.lowercased())"

    let base: URL
    switch layout {
    case "topic": base = root.appendingPathComponent(name.folder)
    case "both": base = root.appendingPathComponent(name.folder).appendingPathComponent(day)
    default: base = root.appendingPathComponent(day)
    }
    return base.appendingPathComponent(filename)
}

/// Never overwrite: bump to `name-2.ext`, `name-3.ext`, ...
/// Never overwrite: bump to `name-2.ext`, `name-3.ext`, ... Also treats paths
/// already claimed earlier in this run as taken, since two screenshots can
/// legitimately want the same name before either exists on disk.
func unique(_ url: URL, reserved: Set<String> = []) -> URL {
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

struct Plan {
    var actions: [Action] = []
    var duplicates: [URL] = []
    var skipped: Int = 0
}

func buildPlan(files: [URL], options: Options, config: Config) -> Plan {
    guard !files.isEmpty else { return Plan() }
    let destination = options.destination ?? URL(fileURLWithPath: config.destination)
    let layout = options.layout ?? config.layout

    if !options.quiet {
        FileHandle.standardError.write(Data(dim("analyzing \(files.count) image(s) with on-device Vision...\n").utf8))
    }

    let analyzed = analyzeAll(files, languages: config.languages) { done, total in
        guard !options.quiet, isTTY else { return }
        FileHandle.standardError.write(Data("\u{001B}[2m\r  \(done)/\(total)\u{001B}[0m".utf8))
    }
    if !options.quiet, isTTY {
        FileHandle.standardError.write(Data("\r\u{001B}[K".utf8))
    }

    var plan = Plan()
    var reserved = Set<String>()
    var seenHashes: [String: URL] = [:]

    for (url, result) in analyzed {
        switch result {
        case .failure(let error):
            plan.skipped += 1
            FileHandle.standardError.write(Data(yellow("skipped \(url.lastPathComponent): \(error)\n").utf8))
        case .success(let facts):
            if let hash = contentHash(url) {
                if let original = seenHashes[hash] {
                    plan.duplicates.append(url)
                    if !options.quiet {
                        FileHandle.standardError.write(Data(
                            dim("duplicate \(url.lastPathComponent) (same as \(original.lastPathComponent))\n").utf8))
                    }
                    continue
                }
                seenHashes[hash] = url
            }

            let isCapture = looksLikeScreenshot(url)
            // Prefer a different title over "-2" when two shots collide.
            let date = timestampInName(url) ?? facts.creationDate
            guard var name = Namer.name(for: facts, extra: config.extraRules, isCapture: isCapture)
            else {
                plan.skipped += 1
                continue
            }
            var target = destinationURL(
                for: facts, name: name, root: destination, layout: layout, date: date)

            // Prefer a different title over "-2" when two shots collide.
            var attempt = 1
            while reserved.contains(target.path)
                || FileManager.default.fileExists(atPath: target.path) {
                guard attempt < 6,
                      let candidate = Namer.name(
                        for: facts, extra: config.extraRules, isCapture: isCapture, attempt: attempt)
                else { break }
                name = candidate
                target = destinationURL(
                    for: facts, name: name, root: destination, layout: layout, date: date)
                attempt += 1
            }
            if reserved.contains(target.path) || FileManager.default.fileExists(atPath: target.path) {
                target = unique(target, reserved: reserved)
            }
            reserved.insert(target.path)
            plan.actions.append(
                Action(source: url, destination: target, facts: facts, name: name, date: date))
        }
    }
    return plan
}

// MARK: - Commands

let usage = """
\(bold("shots")) — describe and file your macOS screenshots with on-device Vision AI.

\(bold("USAGE"))
  shots plan [options]        show what would happen (nothing is moved)
  shots apply [--yes] [options]
  shots undo                  move the last applied batch back
  shots list                  list previous batches
  shots watch [--interval 30] keep filing new screenshots in the background
  shots agent [install|uninstall|status]
                              run `watch` automatically at login (launchd)
  shots config [--print|--edit|--layout day|topic|both|--add-source DIR]

\(bold("OPTIONS"))
  -d, --dir DIR      folder to scan (repeatable, default from config)
      --to DIR       destination root (default ~/Screenshots)
      --layout MODE  day (default) | topic | both
      --all          include images that do not look like screenshots
  -y, --yes          required before anything is moved
      --json         machine-readable output for `plan`
  -q, --quiet        no progress output

\(bold("LAYOUTS"))
  day    ~/Screenshots/2026-11-06/2026-11-06-1345-grafana-cpu-panel.png
  topic  ~/Screenshots/monitoring/2026-11-06-1345-grafana-cpu-panel.png
  both   ~/Screenshots/monitoring/2026-11-06/2026-11-06-1345-grafana-cpu-panel.png
"""

func runPlan(_ options: Options, config: Config, apply: Bool) {
    let files = collect(options, config: config)
    guard !files.isEmpty else {
        print(dim("nothing to do — no new screenshots found"))
        return
    }
    let plan = buildPlan(files: files, options: options, config: config)
    guard !plan.actions.isEmpty else {
        print(dim("nothing to do"))
        return
    }

    if options.json {
        let payload = plan.actions.map { action -> [String: String] in
            [
                "source": action.source.path,
                "destination": action.destination.path,
                "folder": action.name.folder,
                "created": ISO8601DateFormatter().string(from: action.date),
            ]
        }
        let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data ?? Data(), encoding: .utf8) ?? "[]")
        if !apply { return }
    } else {
        let root = (options.destination ?? URL(fileURLWithPath: config.destination)).path
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        var groups: [String: [Action]] = [:]
        for action in plan.actions {
            let key = action.destination.deletingLastPathComponent().path
                .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            groups[key, default: []].append(action)
        }
        print("")
        for key in groups.keys.sorted() {
            print(bold(key + "/"))
            for action in groups[key]!.sorted(by: { $0.destination.path < $1.destination.path }) {
                print("  \(action.destination.lastPathComponent)")
                print(dim("    ← \(action.source.lastPathComponent)  [\(action.name.folder)]"))
            }
        }
        print("")
        print(dim("\(plan.actions.count) file(s) → \(root)"))
        if !plan.duplicates.isEmpty {
            print(dim("  \(plan.duplicates.count) duplicate(s) left in place"))
        }
    }

    guard apply else {
        print(dim("dry run only — run `shots apply --yes` to move them"))
        return
    }

    if !options.yes {
        print("")
        print("This will move \(plan.actions.count) file(s). Re-run with \(bold("--yes")) to confirm.")
        return
    }

    var moves: [Move] = []
    var failures = 0
    for action in plan.actions {
        do {
            try FileManager.default.createDirectory(
                at: action.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let final = unique(action.destination)
            try FileManager.default.moveItem(at: action.source, to: final)
            moves.append(Move(from: action.source.path, to: final.path))
        } catch {
            failures += 1
            FileHandle.standardError.write(Data(red("failed \(action.source.lastPathComponent): \(error.localizedDescription)\n").utf8))
        }
    }

    if !moves.isEmpty {
        let entry = JournalEntry(
            date: Date(),
            destination: (options.destination ?? URL(fileURLWithPath: config.destination)).path,
            moves: moves)
        try? Journal.write(entry)
    }

    print(green("moved \(moves.count) file(s)") + (failures > 0 ? red(", \(failures) failed") : ""))
    if !moves.isEmpty { print(dim("undo with `shots undo`")) }
}

func runUndo() {
    guard let (url, entry) = Journal.entries().first else {
        print(dim("no batches to undo"))
        return
    }
    var restored = 0
    var skipped = 0
    for move in entry.moves {
        let from = URL(fileURLWithPath: move.to)
        let to = URL(fileURLWithPath: move.from)
        guard FileManager.default.fileExists(atPath: from.path) else { skipped += 1; continue }
        let target = unique(to)
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
    print(green("restored \(restored) file(s)") + (skipped > 0 ? dim(", \(skipped) skipped") : ""))
    print(dim("batch from \(ISO8601DateFormatter().string(from: entry.date))"))
}

func runList() {
    let entries = Journal.entries()
    guard !entries.isEmpty else {
        print(dim("no batches yet"))
        return
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    for (_, entry) in entries {
        let folder = entry.destination
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        print("\(bold(formatter.string(from: entry.date)))  \(entry.moves.count) file(s)  → \(folder)")
    }
}

func runWatch(_ options: Options, config: Config, interval: TimeInterval) {
    let root = (options.destination ?? URL(fileURLWithPath: config.destination)).path
    print(bold("watching ") + config.sources.joined(separator: ", ") + dim(" → \(root), every \(Int(interval))s"))
    print(dim("ctrl-c to stop"))
    while true {
        var local = options
        local.quiet = true
        let files = collect(local, config: config).filter { url in
            // Give the screenshot tool a moment to finish writing the file.
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { return false }
            return Date().timeIntervalSince(modified) > 5
        }
        if !files.isEmpty {
            let plan = buildPlan(files: files, options: local, config: config)
            var moves: [Move] = []
            for action in plan.actions {
                do {
                    try FileManager.default.createDirectory(
                        at: action.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let final = unique(action.destination)
                    try FileManager.default.moveItem(at: action.source, to: final)
                    moves.append(Move(from: action.source.path, to: final.path))
                    print("\(green("filed")) \(final.lastPathComponent)")
                } catch {
                    print(red("failed") + " \(action.source.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if !moves.isEmpty {
                try? Journal.write(JournalEntry(date: Date(), destination: root, moves: moves))
            }
        }
        Thread.sleep(forTimeInterval: interval)
    }
}

func runConfig(_ arguments: [String], config: Config) {
    var config = config
    var index = 0
    if arguments.isEmpty || arguments.contains("--print") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            print(String(data: data, encoding: .utf8) ?? "{}")
        }
        print(dim("\nfile: \(Config.defaultPath.path)"))
        return
    }
    while index < arguments.count {
        switch arguments[index] {
        case "--layout":
            index += 1
            guard index < arguments.count, ["day", "topic", "both"].contains(arguments[index]) else {
                fail("--layout expects day, topic or both")
            }
            config.layout = arguments[index]
        case "--add-source":
            index += 1
            guard index < arguments.count else { fail("--add-source expects a directory") }
            let path = (arguments[index] as NSString).expandingTildeInPath
            if !config.sources.contains(path) { config.sources.append(path) }
        case "--remove-source":
            index += 1
            guard index < arguments.count else { fail("--remove-source expects a directory") }
            let path = (arguments[index] as NSString).expandingTildeInPath
            config.sources.removeAll { $0 == path }
        case "--destination":
            index += 1
            guard index < arguments.count else { fail("--destination expects a directory") }
            config.destination = (arguments[index] as NSString).expandingTildeInPath
        case "--edit":
            try? config.save()
            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vim"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [editor, Config.defaultPath.path]
            try? process.run()
            process.waitUntilExit()
            return
        default:
            fail("unknown config option \(arguments[index])")
        }
        index += 1
    }
    do {
        try config.save()
        print(green("saved ") + Config.defaultPath.path)
    } catch {
        fail("could not save config: \(error.localizedDescription)")
    }
}

// MARK: - Background agent

let agentLabel = "com.teveus.shots"
let agentPlist = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")

func runAgent(_ arguments: [String]) {
    let action = arguments.first ?? "status"
    // argv[0] is just "shots" when run from PATH, so ask the bundle for the real path.
    let executable = Bundle.main.executablePath
        ?? URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let uid = getuid()

    func launchctl(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    switch action {
    case "install":
        let config = Config.load()
        let sources = config.sources
            .map { "\n    <string>--dir</string>\n    <string>\($0)</string>" }
            .joined()
        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>\(agentLabel)</string>
  <key>ProgramArguments</key>
  <array>
    <string>\(executable)</string>
    <string>watch</string>
    <string>--interval</string>
    <string>60</string>\(sources)
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>\(home)/.local/share/shots/agent.log</string>
  <key>StandardErrorPath</key><string>\(home)/.local/share/shots/agent.log</string>
</dict>
</plist>
"""
        do {
            try FileManager.default.createDirectory(
                at: agentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Journal.directory, withIntermediateDirectories: true)
            try plist.write(to: agentPlist, atomically: true, encoding: .utf8)

            launchctl(["bootout", "gui/\(uid)/\(agentLabel)"])
            launchctl(["bootstrap", "gui/\(uid)", agentPlist.path])
            launchctl(["enable", "gui/\(uid)/\(agentLabel)"])
            launchctl(["kickstart", "-k", "gui/\(uid)/\(agentLabel)"])
            print(green("agent installed ") + dim(agentPlist.path))
            print(dim("new screenshots are filed within a minute; log: ~/.local/share/shots/agent.log"))
        } catch {
            fail("could not install agent: \(error.localizedDescription)")
        }

    case "uninstall":
        launchctl(["bootout", "gui/\(uid)/\(agentLabel)"])
        try? FileManager.default.removeItem(at: agentPlist)
        print(green("agent removed"))

    default:
        if FileManager.default.fileExists(atPath: agentPlist.path) {
            print("agent: \(green("installed")) " + dim(agentPlist.path))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["print", "gui/\(uid)/\(agentLabel)"]
            try? process.run()
            process.waitUntilExit()
        } else {
            print("agent: not installed " + dim("(install with `shots agent install`)"))
        }
    }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())
let (command, options) = parse(arguments)
var config = Config.load()

switch command {
case "plan", "scan", "dry-run":
    runPlan(options, config: config, apply: false)
case "apply", "move":
    runPlan(options, config: config, apply: true)
case "undo":
    runUndo()
case "list", "batches":
    runList()
case "watch", "daemon":
    runWatch(options, config: config, interval: options.interval)
case "config":
    let rest = arguments.drop(while: { $0 != "config" }).dropFirst()
    runConfig(Array(rest), config: config)
case "agent":
    let rest = arguments.drop(while: { $0 != "agent" }).dropFirst()
    runAgent(Array(rest))
case "version":
    print("shots 1.0.0")
case "debug":
    let path = arguments.dropFirst().first { !$0.hasPrefix("-") } ?? ""
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard let facts = try? analyze(url, languages: config.languages) else {
        fail("cannot decode \(url.path)")
    }
    print("size: \(facts.width)x\(facts.height)  screenshot=\(facts.isScreenshot)")
    print("classes: " + facts.classes.prefix(5).map { "\($0.label) \(String(format: "%.2f", $0.confidence))" }.joined(separator: ", "))
    print("lines:")
    for (i, line) in facts.lines.enumerated() { print("  \(i): \(line)") }
    let isCapture = looksLikeScreenshot(url)
    if let name = Namer.name(for: facts, extra: config.extraRules, isCapture: isCapture) {
        print("=> \(name.folder)/\(name.stem)")
    } else {
        print("=> (no distinct name; would be filed as a duplicate)")
    }
default:
    print(usage)
}
