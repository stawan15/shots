import AppKit
import Foundation
import ShotsCore

/// State for the menu-bar app: the pending plan, the config, and the actions the
/// UI exposes. All filing logic lives in `ShotsCore`, so the CLI and the app behave
/// identically. Delegates instead of observations, because this toolchain has no
/// SwiftUI macros and plain AppKit controllers are simpler to reason about anyway.
final class ShotsStore {
    var onChange: (() -> Void)?
    var onStatus: ((String) -> Void)?

    private(set) var plan = Shots.Plan()
    private(set) var isScanning = false
    private(set) var config = Config.load()
    private(set) var selected = Set<String>()
    private(set) var statusLine = ""

    private var autoTimer: Timer?
    private let queue = DispatchQueue(label: "com.teveus.shots.scan", qos: .userInitiated)

    var destinationRoot: URL { URL(fileURLWithPath: config.destination) }
    var selectedItems: [Shots.PlanItem] { plan.items.filter { selected.contains($0.id) } }

    var autoFile: Bool {
        get { UserDefaults.standard.bool(forKey: "autoFile") }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoFile")
            restartAutoTimer()
        }
    }

    init() {
        if autoFile { restartAutoTimer() }
    }

    // MARK: Scanning

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        statusLine = "Looking for screenshots…"
        onChange?()

        let sources = config.sources.map { URL(fileURLWithPath: $0) }
        let destination = destinationRoot
        let layout = config.layout
        let rules = config.extraRules
        let languages = config.languages

        queue.async { [weak self] in
            let scan = Shots.scan(sources: sources, destination: destination, includeAll: false)
            let plan = Shots.plan(
                files: scan.files,
                destination: destination,
                layout: layout,
                rules: rules,
                languages: languages
            ) { done, total in
                DispatchQueue.main.async {
                    self?.statusLine = "Reading \(done) of \(total)…"
                    self?.onChange?()
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.plan = plan
                // Everything found is pre-selected: the common case is "yes, all".
                self.selected = Set(plan.items.map(\.id))
                self.isScanning = false
                self.statusLine = plan.isEmpty
                    ? "All caught up — nothing new."
                    : "\(plan.items.count) screenshot(s) ready to file."
                self.onChange?()
            }
        }
    }

    // MARK: Actions

    func apply() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        do {
            let moves = try Shots.apply(items, destinationRoot: destinationRoot.path)
            statusLine = "Filed \(moves.count) screenshot(s)."
            onChange?()
            refresh()
        } catch {
            statusLine = "Could not file: \(error.localizedDescription)"
            onChange?()
        }
    }

    func undoLast() {
        if let result = Journal.undoLast() {
            statusLine = "Restored \(result.restored) file(s) to \(result.skipped) skipped."
            // Only mention skipped when there is something to mention.
            if result.skipped == 0 { statusLine = "Restored \(result.restored) file(s)." }
        } else {
            statusLine = "Nothing to undo."
        }
        onChange?()
        refresh()
    }

    func hasUndo() -> Bool { !Journal.entries().isEmpty }

    func toggle(_ item: Shots.PlanItem) {
        if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
        onChange?()
    }

    func selectAll(_ flag: Bool) {
        selected = flag ? Set(plan.items.map(\.id)) : []
        onChange?()
    }

    // MARK: Config

    func setSources(_ sources: [String]) { config.sources = sources; persist() }
    func setDestination(_ path: String) { config.destination = path; persist() }
    func setLayout(_ layout: String) { config.layout = layout; persist() }

    func addRule(folder: String, tag: String, keywords: [String]) {
        let cleanFolder = folder.trimmingCharacters(in: .whitespaces)
        let list = keywords
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !cleanFolder.isEmpty, !list.isEmpty else { return }
        let cleanTag = tag.trimmingCharacters(in: .whitespaces).lowercased()
        config.rules.append(.init(
            folder: cleanFolder,
            tag: cleanTag.isEmpty
                ? (cleanFolder.split(separator: "/").last.map(String.init) ?? "custom")
                : cleanTag,
            keywords: list))
        persist()
    }

    func removeRule(at index: Int) {
        guard config.rules.indices.contains(index) else { return }
        config.rules.remove(at: index)
        persist()
    }

    func reloadConfig() {
        config = Config.load()
        onChange?()
    }

    private func persist() {
        do {
            try config.save()
            statusLine = "Settings saved."
        } catch {
            statusLine = "Could not save: \(error.localizedDescription)"
        }
        onChange?()
        refresh()
    }

    // MARK: Helpers

    func revealInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openDestination() { NSWorkspace.shared.open(destinationRoot) }

    private func restartAutoTimer() {
        autoTimer?.invalidate()
        autoTimer = nil
        guard autoFile else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, !self.isScanning else { return }
            self.refresh()
            // Give the scan a moment, then file whatever it found.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, !self.plan.isEmpty, !self.isScanning else { return }
                self.apply()
            }
        }
    }
}
