import AppKit
import ShotsCore

/// The table row shown in the popover: checkbox, thumbnail, new name, source name,
/// and the folder badge.
final class ItemRowView: NSTableCellView {
    private let checkbox = NSButton()
    private let thumbnail = NSImageView()
    private let newNameLabel = NSTextField(labelWithString: "")
    private let originalLabel = NSTextField(labelWithString: "")
    private let folderBadge = BadgeView()
    private let revealButton = NSButton()

    private var item: Shots.PlanItem?
    private var onToggle: (() -> Void)?
    private var onReveal: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        checkbox.setButtonType(.switch)
        checkbox.title = ""
        checkbox.target = self
        checkbox.action = #selector(toggleClicked)

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 5
        thumbnail.layer?.borderWidth = 1
        thumbnail.layer?.borderColor = NSColor.separatorColor.cgColor
        thumbnail.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
        thumbnail.layer?.masksToBounds = true

        newNameLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        newNameLabel.lineBreakMode = .byTruncatingMiddle
        newNameLabel.textColor = .labelColor

        originalLabel.font = .systemFont(ofSize: 10)
        originalLabel.textColor = .secondaryLabelColor
        originalLabel.lineBreakMode = .byTruncatingMiddle

        revealButton.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Show in Finder")
        revealButton.isBordered = false
        revealButton.target = self
        revealButton.action = #selector(revealClicked)
        revealButton.contentTintColor = .tertiaryLabelColor

        for view in [checkbox, thumbnail, newNameLabel, originalLabel, folderBadge, revealButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),

            thumbnail.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 68),
            thumbnail.heightAnchor.constraint(equalToConstant: 46),

            newNameLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 10),
            newNameLabel.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 1),
            newNameLabel.trailingAnchor.constraint(equalTo: revealButton.leadingAnchor, constant: -6),

            originalLabel.leadingAnchor.constraint(equalTo: newNameLabel.leadingAnchor),
            originalLabel.topAnchor.constraint(equalTo: newNameLabel.bottomAnchor, constant: 1),
            originalLabel.trailingAnchor.constraint(equalTo: newNameLabel.trailingAnchor),

            folderBadge.leadingAnchor.constraint(equalTo: newNameLabel.leadingAnchor),
            folderBadge.topAnchor.constraint(equalTo: originalLabel.bottomAnchor, constant: 3),
            folderBadge.bottomAnchor.constraint(lessThanOrEqualTo: thumbnail.bottomAnchor),

            revealButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            revealButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            revealButton.widthAnchor.constraint(equalToConstant: 16),
        ])
    }

    func configure(
        item: Shots.PlanItem,
        selected: Bool,
        onToggle: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) {
        self.item = item
        self.onToggle = onToggle
        self.onReveal = onReveal

        checkbox.state = selected ? .on : .off
        newNameLabel.stringValue = item.newName
        originalLabel.stringValue = item.originalName
        folderBadge.text = item.folder
        thumbnail.image = Thumbnails.image(for: item.source)

        // Dim rows that are excluded from the pending action.
        let alpha: CGFloat = selected ? 1 : 0.45
        thumbnail.alphaValue = alpha
        newNameLabel.alphaValue = alpha
        originalLabel.alphaValue = alpha
        folderBadge.alphaValue = alpha
    }

    @objc private func toggleClicked() { onToggle?() }
    @objc private func revealClicked() { onReveal?() }
}

/// A small rounded label used for the topic folder name.
final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = .controlAccentColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    required init?(coder: NSCoder) { nil }
}
