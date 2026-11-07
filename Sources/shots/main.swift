import Foundation
import ShotsCore

// MARK: - Terminal helpers

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

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Options

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

    func value() -> String {
        index += 1
        guard index < arguments.count else { fail("missing value for \(arguments[index - 1])") }
        return arguments[index]
    }

    while index < arguments.count {
        let arg = arguments[index]
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

extension Options {
    var sourceURLs: [URL] {
        sources.isEmpty ? [] : sources
    }
}

let usage = """
\(bold("shots")) — describe and file your macOS screenshots with on-device Vision AI.

\(bold("USAGE"))
  shots plan [options]        show what would happen (nothing is moved)
  shots apply [--yes] [options]
  shots undo                  move the last applied batch back
  shots list                  list previous batches
  shots watch [--interval 30] keep filing new screenshots in the background
  shots agent install|status|log|uninstall
                              run `watch` automatically at login (launchd)
  shots config [--print|--edit|--layout day|topic|both|--add-source DIR]
  shots debug PATH            show OCR, Vision labels and the chosen name
  shots version

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

\(bold("FILES"))
  ~/.config/shots/config.json          sources, destination, layout, custom rules
  ~/.local/share/shots/journal-*.json  undo journals, one per batch
"""

// MARK: - plan / apply

func buildPlan(_ options: Options, config: Config) -> Shots.Plan {
    let destination = options.destination ?? URL(fileURLWithPath: config.destination)
    let scan = Shots.scan(
        sources: options.sources.isEmpty ? config.sources.map { URL(fileURLWithPath: $0) } : options.sources,
        destination: destination,
        includeAll: options.all)

    if !options.quiet {
        for dir in scan.missing { note(yellow("no such folder: \(dir.path)")) }
        note(dim("analyzing \(scan.files.count) image(s) with on-device Vision..."))
    }

    let plan = Shots.plan(
        files: scan.files,
        destination: destination,
        layout: options.layout ?? config.layout,
        rules: config.extraRules,
        languages: config.languages
    ) { done, total in
        guard !options.quiet, isTTY else { return }
        note("\u{001B}[2m\r  \(done)/\(total)\u{001B}[0m")
    }
    if !options.quiet, isTTY { note("\r\u{001B}[K") }
    return plan
}

func runPlan(_ options: Options, config: Config, apply shouldApply: Bool) {
    let destinationRoot = (options.destination ?? URL(fileURLWithPath: config.destination)).path
    let plan = buildPlan(options, config: config)

    guard !plan.isEmpty else {
        for url in plan.skipped { note(yellow("skipped \(url.lastPathComponent)")) }
        print(dim("nothing to do — no new screenshots found"))
        return
    }

    if options.json {
        let payload = plan.items.map { item -> [String: String] in
            [
                "source": item.source.path,
                "destination": item.destination.path,
                "folder": item.folder,
                "created": ISO8601DateFormatter().string(from: item.date),
            ]
        }
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data ?? Data(), encoding: .utf8) ?? "[]")
        if !shouldApply { return }
    } else {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var groups: [String: [Shots.PlanItem]] = [:]
        for item in plan.items {
            let key = item.destination.deletingLastPathComponent().path
                .replacingOccurrences(of: home, with: "~")
            groups[key, default: []].append(item)
        }
        print("")
        for key in groups.keys.sorted() {
            print(bold(key + "/"))
            for item in groups[key]!.sorted(by: { $0.destination.path < $1.destination.path }) {
                print("  \(item.newName)")
                print(dim("    ← \(item.originalName)  [\(item.folder)]"))
            }
        }
        print("")
        print(dim("\(plan.items.count) file(s) → \(destinationRoot.replacingOccurrences(of: home, with: "~"))"))
        if !plan.duplicates.isEmpty {
            print(dim("  \(plan.duplicates.count) duplicate(s) left in place"))
        }
    }

    guard shouldApply else {
        print(dim("dry run only — run `shots apply --yes` to move them"))
        return
    }

    guard options.yes else {
        print("")
        print("This will move \(plan.items.count) file(s). Re-run with \(bold("--yes")) to confirm.")
        return
    }

    do {
        let moves = try Shots.apply(plan.items, destinationRoot: destinationRoot)
        print(green("moved \(moves.count) file(s)"))
        print(dim("undo with `shots undo`"))
    } catch {
        fail("move failed: \(error.localizedDescription)")
    }
}

// MARK: - undo / list

func runUndo() {
    guard let result = Journal.undoLast() else {
        print(dim("no batches to undo"))
        return
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    print(green("restored \(result.restored) file(s)")
        + (result.skipped > 0 ? dim(", \(result.skipped) skipped") : ""))
    print(dim("batch from \(formatter.string(from: result.date))"))
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
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    for (_, entry) in entries {
        let folder = entry.destination.replacingOccurrences(of: home, with: "~")
        print("\(bold(formatter.string(from: entry.date)))  \(entry.moves.count) file(s)  → \(folder)")
    }
}

// MARK: - watch

func runWatch(_ options: Options, config: Config, interval: TimeInterval) {
    let root = (options.destination ?? URL(fileURLWithPath: config.destination)).path
    let sources = options.sources.isEmpty ? config.sources : options.sources.map(\.path)
    print(bold("watching ") + sources.joined(separator: ", ")
        + dim(" → \(root.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")), every \(Int(interval))s"))
    print(dim("ctrl-c to stop"))

    while true {
        let destination = options.destination ?? URL(fileURLWithPath: config.destination)
        let scan = Shots.scan(
            sources: options.sources.isEmpty ? config.sources.map { URL(fileURLWithPath: $0) } : options.sources,
            destination: destination,
            includeAll: options.all)

        // Wait a few seconds so the screenshot tool can finish writing the file.
        let ready = scan.files.filter { url in
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { return false }
            return Date().timeIntervalSince(modified) > 5
        }

        if !ready.isEmpty {
            let plan = Shots.plan(
                files: ready, destination: destination, layout: options.layout ?? config.layout,
                rules: config.extraRules, languages: config.languages)
            if let moves = try? Shots.apply(plan.items, destinationRoot: root) {
                for move in moves { print("\(green("filed")) \(URL(fileURLWithPath: move.to).lastPathComponent)") }
            }
        }
        Thread.sleep(forTimeInterval: interval)
    }
}

// MARK: - config

func runConfig(_ arguments: [String], config: Config) {
    var config = config
    var index = 0

    func printConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            print(String(data: data, encoding: .utf8) ?? "{}")
        }
        print(dim("\nfile: \(Config.defaultPath.path)"))
    }

    if arguments.isEmpty || arguments == ["--print"] {
        printConfig()
        return
    }

    while index < arguments.count {
        switch arguments[index] {
        case "--print":
            break   // applied after any changes on the same command line
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
            do {
                try config.save()
            } catch {
                fail("could not write config: \(error.localizedDescription)")
            }
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
        if arguments.contains("--print") {
            printConfig()
        } else {
            print(green("saved ") + Config.defaultPath.path)
        }
    } catch {
        fail("could not save config: \(error.localizedDescription)")
    }
}

// MARK: - launchd agent

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

    case "log":
        let log = Journal.directory.appendingPathComponent("agent.log")
        guard let text = try? String(contentsOf: log, encoding: .utf8) else {
            print(dim("no agent log yet"))
            return
        }
        print(text.split(separator: "\n").suffix(40).joined(separator: "\n"))

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

// MARK: - debug

func runDebug(_ arguments: [String], config: Config) {
    guard let path = arguments.first else { fail("debug needs an image path") }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard let facts = try? analyze(url, languages: config.languages) else {
        fail("cannot decode \(url.path)")
    }
    print("size: \(facts.width)x\(facts.height)  screenshot=\(facts.isScreenshot)")
    print("classes: " + facts.classes.prefix(5)
        .map { "\($0.label) \(String(format: "%.2f", $0.confidence))" }
        .joined(separator: ", "))
    print("lines:")
    for (i, line) in facts.lines.enumerated() { print("  \(i): \(line)") }
    if let name = Namer.name(
        for: facts, extra: config.extraRules, isCapture: Shots.looksLikeScreenshot(url)) {
        print("=> \(name.folder)/\(name.stem)")
    } else {
        print("=> (no distinct name; would be filed as a duplicate)")
    }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())
var config = Config.load()

// `config` and `agent` take their own subcommand flags (--add-source, install),
// so they are dispatched before the global option parser sees them.
switch arguments.first {
case "config":
    runConfig(Array(arguments.dropFirst()), config: config)
    exit(0)
case "agent":
    runAgent(Array(arguments.dropFirst()))
    exit(0)
default:
    break
}

let (command, options) = parse(arguments)

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
case "debug":
    runDebug(Array(arguments.dropFirst()), config: config)
case "version":
    print("shots \(ShotsVersion.current)")
default:
    print(usage)
}
