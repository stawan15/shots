import AppKit
import ShotsCore

/// Settings window in plain AppKit: source folders, destination, layout, and the
/// custom naming rules. A separate window so the popover can open it on demand.
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func show(store: ShotsStore) {
        if let shared {
            shared.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            shared.reload()
            return
        }
        let controller = SettingsWindowController(store: store)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private let store: ShotsStore
    private let sourcesTable = NSTableView()
    private let destinationLabel = NSTextField(labelWithString: "")
    private let layoutControl = NSSegmentedControl(
        labels: ["Day", "Topic", "Topic + Day"], trackingMode: .selectOne, target: nil, action: nil)
    private let rulesStack = NSStackView()
    private let folderField = NSTextField()
    private let tagField = NSTextField()
    private let keywordsField = NSTextField()

    init(store: ShotsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Shots Settings"
        window.isReleasedWhenClosed = true
        window.center()
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { nil }

    func reload() {
        render()
    }

    // MARK: Layout

    private func build() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        stack.addArrangedSubview(sectionLabel("Folders to watch"))

        sourcesTable.headerView = nil
        sourcesTable.rowHeight = 22
        sourcesTable.dataSource = self
        sourcesTable.delegate = self
        let column = NSTableColumn(identifier: .init("source"))
        column.resizingMask = .autoresizingMask
        sourcesTable.addTableColumn(column)
        let scroll = NSScrollView()
        scroll.documentView = sourcesTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 96).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 468).isActive = true
        stack.addArrangedSubview(scroll)

        let sourceButtons = NSStackView()
        sourceButtons.orientation = .horizontal
        sourceButtons.spacing = 6
        sourceButtons.addArrangedSubview(button("Add Folder…", #selector(addSource)))
        sourceButtons.addArrangedSubview(button("Remove", #selector(removeSource)))
        stack.addArrangedSubview(sourceButtons)

        stack.addArrangedSubview(spacer(10))
        stack.addArrangedSubview(sectionLabel("Where filed screenshots go"))

        destinationLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        destinationLabel.lineBreakMode = .byTruncatingMiddle
        destinationLabel.translatesAutoresizingMaskIntoConstraints = false
        destinationLabel.widthAnchor.constraint(equalToConstant: 380).isActive = true
        let destRow = NSStackView()
        destRow.orientation = .horizontal
        destRow.spacing = 6
        destRow.addArrangedSubview(destinationLabel)
        destRow.addArrangedSubview(button("Change…", #selector(changeDestination)))
        stack.addArrangedSubview(destRow)

        layoutControl.target = self
        layoutControl.action = #selector(layoutChanged)
        stack.addArrangedSubview(layoutControl)

        stack.addArrangedSubview(spacer(10))
        stack.addArrangedSubview(sectionLabel("Custom rules"))

        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 6
        stack.addArrangedSubview(rulesStack)

        let ruleRow = NSStackView()
        ruleRow.orientation = .horizontal
        ruleRow.spacing = 6
        folderField.placeholderString = "folder"
        folderField.translatesAutoresizingMaskIntoConstraints = false
        folderField.widthAnchor.constraint(equalToConstant: 130).isActive = true
        tagField.placeholderString = "tag"
        tagField.translatesAutoresizingMaskIntoConstraints = false
        tagField.widthAnchor.constraint(equalToConstant: 100).isActive = true
        ruleRow.addArrangedSubview(folderField)
        ruleRow.addArrangedSubview(tagField)
        ruleRow.addArrangedSubview(button("Add Rule", #selector(addRule)))
        stack.addArrangedSubview(ruleRow)

        keywordsField.placeholderString = "keywords, comma separated"
        keywordsField.translatesAutoresizingMaskIntoConstraints = false
        keywordsField.widthAnchor.constraint(equalToConstant: 456).isActive = true
        stack.addArrangedSubview(keywordsField)

        let hint = NSTextField(labelWithString: "A screenshot containing any keyword starts with the tag.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
        ])

        render()
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    private func render() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        destinationLabel.stringValue = store.config.destination.replacingOccurrences(of: home, with: "~")
        switch store.config.layout {
        case "topic": layoutControl.selectedSegment = 1
        case "both": layoutControl.selectedSegment = 2
        default: layoutControl.selectedSegment = 0
        }
        sourcesTable.reloadData()

        for view in rulesStack.arrangedSubviews { view.removeFromSuperview() }
        for (index, rule) in store.config.rules.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            let label = NSTextField(labelWithString: "\(rule.tag) → \(rule.folder)   (\(rule.keywords.joined(separator: ", ")))")
            label.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
            row.addArrangedSubview(label)
            let remove = NSButton(title: "✕", target: self, action: #selector(removeRuleClicked(_:)))
            remove.bezelStyle = .inline
            remove.tag = index
            row.addArrangedSubview(remove)
            rulesStack.addArrangedSubview(row)
        }
        if store.config.rules.isEmpty {
            let empty = NSTextField(labelWithString: "No custom rules yet.")
            empty.font = .systemFont(ofSize: 10)
            empty.textColor = .tertiaryLabelColor
            rulesStack.addArrangedSubview(empty)
        }
    }

    // MARK: Actions

    @objc private func addSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !store.config.sources.contains(url.path) else { return }
        store.setSources(store.config.sources + [url.path])
        render()
    }

    @objc private func removeSource() {
        let row = sourcesTable.selectedRow
        guard store.config.sources.indices.contains(row) else { return }
        var sources = store.config.sources
        sources.remove(at: row)
        store.setSources(sources)
        render()
    }

    @objc private func changeDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setDestination(url.path)
        render()
    }

    @objc private func layoutChanged() {
        let mode = ["day", "topic", "both"][max(0, min(2, layoutControl.selectedSegment))]
        store.setLayout(mode)
    }

    @objc private func addRule() {
        let keywords = keywordsField.stringValue
            .split(separator: ",")
            .map(String.init)
        store.addRule(folder: folderField.stringValue, tag: tagField.stringValue, keywords: keywords)
        folderField.stringValue = ""
        tagField.stringValue = ""
        keywordsField.stringValue = ""
        render()
    }

    @objc private func removeRuleClicked(_ sender: NSButton) {
        store.removeRule(at: sender.tag)
        render()
    }
}

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        store.config.sources.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let label = NSTextField(labelWithString:
            store.config.sources[row].replacingOccurrences(of: home, with: "~"))
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}
