import AppKit
import ShotsCore

/// Menu-bar entry point. The app has no Dock icon and no main window: it lives as a
/// status item that opens the filing popover. Written in AppKit because the
/// CommandLineTools toolchain on this machine has no SwiftUI macros.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var store: ShotsStore!
    private var controller: PopoverViewController!
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = ShotsStore()
        controller = PopoverViewController(store: store)

        popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        store.onChange = { [weak self] in
            DispatchQueue.main.async { self?.updateBadge() }
        }
        updateBadge()
        UpdateController.checkIfDue()
    }

    /// Left click opens the popover; right click opens a menu with Quit, so the app
    /// can be closed without Force Quit or killing the process.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        closePopover()
        let menu = NSMenu()

        let about = NSMenuItem(title: "About Shots", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let version = NSMenuItem(
            title: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")",
            action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        menu.addItem(.separator())

        let updates = NSMenuItem(
            title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let automatic = NSMenuItem(
            title: "Check Automatically", action: #selector(toggleAutomaticChecks), keyEquivalent: "")
        automatic.target = self
        automatic.state = Updater.automaticChecksEnabled ? .on : .off
        menu.addItem(automatic)

        menu.addItem(.separator())

        let scan = NSMenuItem(title: "Scan Now", action: #selector(scanNow), keyEquivalent: "r")
        scan.target = self
        menu.addItem(scan)

        let folder = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Shots", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attaching the menu before popping it up makes the item highlight behave.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Shots",
            .applicationVersion: version,
            .credits: NSAttributedString(
                string: "Names and files your screenshots on-device with Apple Vision.\nhttps://github.com/stawan15/shots",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        UpdateController.check(interactive: true)
    }

    @objc private func toggleAutomaticChecks() {
        Updater.automaticChecksEnabled.toggle()
    }

    @objc private func scanNow() { store.refresh() }

    @objc private func openFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: store.config.destination))
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// Shows the pending count next to the icon so the work is visible at a glance.
    private func updateBadge() {
        guard let button = statusItem.button else { return }
        let count = store?.plan.items.count ?? 0
        let symbol = count > 0 ? "photo.badge.checkmark" : "photo.on.rectangle.angled"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Shots")
        image?.isTemplate = true
        button.image = image
        button.title = count > 0 ? " \(count)" : ""
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 11, weight: .medium)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
            return
        }
        store.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        // Clicking anywhere else closes it, like a normal menu-bar extra.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

// Top-level entry point: `main.swift` style code so the package can build a plain
// executable without an app bundle wrapper.
let app = NSApplication.shared

// `Shots --preview <path>` renders the popover to a PNG and exits. Used to check
// layout changes without clicking through the UI by hand.
if let flag = CommandLine.arguments.firstIndex(of: "--preview") {
    app.setActivationPolicy(.prohibited)
    let store = ShotsStore()
    let controller = PopoverViewController(store: store)
    controller.loadView()
    controller.viewDidLoad()

    // Wait for the scan to land before rendering, otherwise the preview is empty.
    var waited = 0.0
    while store.isScanning, waited < 60 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        waited += 0.1
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))

    let view = controller.view
    view.frame = NSRect(x: 0, y: 0, width: 470, height: 500)
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        FileHandle.standardError.write(Data("cannot render view\n".utf8))
        exit(1)
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("cannot encode png\n".utf8))
        exit(1)
    }
    let index = flag + 1
    let output = index < CommandLine.arguments.count
        ? CommandLine.arguments[index]
        : "/tmp/shots-preview.png"
    do {
        try data.write(to: URL(fileURLWithPath: output))
        print("wrote \(output) (\(store.plan.items.count) item(s))")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("cannot write \(output)\n".utf8))
        exit(1)
    }
}

// `Shots --install-update <dmg> [--target <app>]` performs the update swap without
// any UI. Used to verify the updater end to end, since the alert flow is not
// reachable from a script.
if let flag = CommandLine.arguments.firstIndex(of: "--install-update") {
    app.setActivationPolicy(.prohibited)
    let dmgPath = flag + 1 < CommandLine.arguments.count ? CommandLine.arguments[flag + 1] : ""
    guard !dmgPath.isEmpty else {
        FileHandle.standardError.write(Data("--install-update needs a dmg path\n".utf8))
        exit(1)
    }
    var target = Bundle.main.bundleURL
    if let targetFlag = CommandLine.arguments.firstIndex(of: "--target"),
       targetFlag + 1 < CommandLine.arguments.count {
        target = URL(fileURLWithPath: CommandLine.arguments[targetFlag + 1])
    }
    print("installing \(dmgPath) -> \(target.path)")
    do {
        try Updater.install(
            dmg: URL(fileURLWithPath: dmgPath), target: target, relaunch: false)
        print("installed")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
        exit(1)
    }
}

// `Shots --once` scans, files everything, and exits. Handy for launchd jobs and for
// checking the app path without touching the UI.
if CommandLine.arguments.contains("--once") {
    app.setActivationPolicy(.prohibited)
    let store = ShotsStore()
    store.refresh()
    var waited = 0.0
    while store.isScanning, waited < 120 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        waited += 0.1
    }
    let found = store.plan.items.count
    if found > 0 {
        store.apply()
        // `apply` refreshes asynchronously; let that settle so the message is real.
        var waited = 0.0
        while store.isScanning, waited < 120 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            waited += 0.1
        }
    }
    print(store.statusLine)
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
