import AppKit
import ShotsCore

/// The update UI: check, tell the user what changed, and install on request.
/// Kept separate from the popover so both the menu and the launch-time check can
/// use it without duplicating the alert logic.
enum UpdateController {
    private static var inFlight = false

    /// Checks for a newer version. When `interactive` is false and there is nothing
    /// new, this stays silent — that is what an automatic background check should do.
    static func check(interactive: Bool) {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        Task { @MainActor in
            do {
                let release = try await Updater.latestRelease()
                Updater.markChecked()
                let current = SemanticVersion(ShotsVersion.current)

                guard release.version > current else {
                    if interactive {
                        presentInfo(
                            title: "You're up to date",
                            message: "Shots \(current) is the latest version.")
                    }
                    return
                }

                presentUpdate(release, current: current)
            } catch {
                // A failed background check is not worth interrupting anyone for.
                if interactive {
                    presentInfo(title: "Couldn't check for updates", message: "\(error)")
                }
            }
        }
    }

    private static func presentUpdate(_ release: Updater.Release, current: SemanticVersion) {
        let alert = NSAlert()
        alert.messageText = "Shots \(release.version) is available"
        alert.informativeText = """
            You have \(current). The new version can be installed now; Shots will \
            restart automatically.

            \(summary(from: release.notes))
            """
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            install(release)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    /// Trims release notes to something readable inside an alert.
    private static func summary(from notes: String) -> String {
        let lines = notes
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("!") }
        return lines.prefix(4).joined(separator: "\n")
    }

    private static func install(_ release: Updater.Release) {
        let alert = NSAlert()
        alert.messageText = "Downloading Shots \(release.version)…"
        alert.informativeText = "This usually takes a few seconds."
        alert.addButton(withTitle: "Cancel")
        // Do not block on this; the download runs in the background and the alert
        // is dismissed when it finishes.
        let window = alert.window

        Task { @MainActor in
            do {
                let dmg = try await Updater.download(release)
                window.orderOut(nil)
                NSApp.abortModal()
                try Updater.install(dmg: dmg)
                // `install` relaunches, so nothing after this runs in practice.
                NSApp.terminate(nil)
            } catch {
                window.orderOut(nil)
                NSApp.abortModal()
                presentInfo(
                    title: "Update failed",
                    message: "\(error)\n\nYou can download it manually from the releases page.")
            }
        }

        alert.runModal()
    }

    private static func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Called at launch: checks at most once a day, silently.
    static func checkIfDue() {
        guard Updater.isCheckDue() else { return }
        // Give the app a moment to settle before touching the network.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            check(interactive: false)
        }
    }
}
