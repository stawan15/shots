import AppKit
import ShotsCore

/// Popover content: header, table of pending screenshots, and the action row.
final class PopoverViewController: NSViewController {
    private let store: ShotsStore

    private let titleLabel = NSTextField(labelWithString: "Screenshots")
    private let statusLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let refreshButton = NSButton()
    private let spinner = NSProgressIndicator()

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "Nothing to file")

    private let settingsButton = NSButton()
    private let openButton = NSButton()
    private let undoButton = NSButton()
    private let fileButton = NSButton()
    private let autoCheckbox = NSButton()

    init(store: ShotsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHeader()
        buildTable()
        buildFooter()
        wireStore()
        store.refresh()
    }

    // MARK: Layout

    private func buildHeader() {
        iconView.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)
        iconView.contentTintColor = .controlAccentColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Rescan")
        refreshButton.isBordered = false
        refreshButton.target = self
        refreshButton.action = #selector(rescan)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        for v in [iconView, titleLabel, statusLabel, refreshButton, spinner] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        let divider = makeDivider()
        view.addSubview(divider)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -1),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            statusLabel.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -6),

            spinner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            spinner.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -6),
            refreshButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
        ])
    }

    private func buildTable() {
        let column = NSTableColumn(identifier: .init("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 62
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAutomaticRowHeights = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 56),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -74),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private func buildFooter() {
        let divider = makeDivider()
        view.addSubview(divider)

        configure(settingsButton, title: "Settings…", action: #selector(openSettings))
        configure(openButton, title: "Open Folder", action: #selector(openDestination))
        configure(undoButton, title: "Undo", action: #selector(undo))
        configure(fileButton, title: "File All", action: #selector(file))
        fileButton.keyEquivalent = "\r"
        fileButton.bezelColor = .controlAccentColor
        fileButton.contentTintColor = .white

        autoCheckbox.setButtonType(.switch)
        autoCheckbox.title = "File new screenshots automatically"
        autoCheckbox.font = .systemFont(ofSize: 10)
        autoCheckbox.target = self
        autoCheckbox.action = #selector(autoToggled)
        autoCheckbox.state = store.autoFile ? .on : .off

        for v in [autoCheckbox, settingsButton, openButton, undoButton, fileButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -68),

            settingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            settingsButton.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),

            openButton.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor, constant: 6),
            openButton.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),

            fileButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            fileButton.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),

            undoButton.trailingAnchor.constraint(equalTo: fileButton.leadingAnchor, constant: -6),
            undoButton.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),

            autoCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            autoCheckbox.topAnchor.constraint(equalTo: settingsButton.bottomAnchor, constant: 8),
            autoCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
        ])
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.target = self
        button.action = action
    }

    private func makeDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    // MARK: Store wiring

    private func wireStore() {
        store.onChange = { [weak self] in
            guard let self else { return }
            self.render()
        }
        store.onStatus = { [weak self] text in
            self?.statusLabel.stringValue = text
        }
    }

    private func render() {
        statusLabel.stringValue = store.statusLine
        spinner.isHidden = !store.isScanning
        if store.isScanning { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        refreshButton.isHidden = store.isScanning

        tableView.reloadData()
        emptyLabel.isHidden = !store.plan.items.isEmpty || store.isScanning
        emptyLabel.stringValue = store.isScanning ? "Reading screenshots…" : "Nothing to file"

        let count = store.selectedItems.count
        fileButton.title = count == store.plan.items.count ? "File All" : "File \(count)"
        fileButton.isEnabled = count > 0 && !store.isScanning
        undoButton.isEnabled = store.hasUndo()
    }

    // MARK: Actions

    @objc private func rescan() { store.refresh() }
    @objc private func file() {
        store.apply()
    }

    @objc private func undo() {
        store.undoLast()
    }

    @objc private func openDestination() {
        store.openDestination()
    }

    @objc private func openSettings() {
        SettingsWindowController.show(store: store)
    }

    @objc private func autoToggled() {
        store.autoFile = autoCheckbox.state == .on
    }
}

// MARK: - Table

extension PopoverViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        store.plan.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ItemRowView")
        let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? ItemRowView)
            ?? ItemRowView()
        view.identifier = identifier

        let item = store.plan.items[row]
        let isSelected = store.selected.contains(item.id)
        view.configure(
            item: item,
            selected: isSelected,
            onToggle: { [weak self] in self?.store.toggle(item) },
            onReveal: { [weak self] in self?.store.revealInFinder(item.source) })
        return view
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        TableRowView()
    }
}

/// Row background that highlights what the pending action will include.
final class TableRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Selection is per-row via the checkbox, so the table never draws one.
    }
}
