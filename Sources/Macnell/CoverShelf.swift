import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A notebook's front cover: leather, spine, elastic band, macnell emblem and a label with title / description
final class CoverView: NSView {
    static let coverSize = NSSize(width: 168, height: 241)   // A5-ish proportions
    static let padding: CGFloat = 8

    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSPoint) -> Void)?   // point in window coordinates

    var notebook: Notebook { didSet { needsDisplay = true } }
    private let isCurrent: Bool
    private let accent: NSColor
    private let scale: CGFloat

    /// `scale` enlarges the whole cover (the closed-notebook screen draws it big)
    init(notebook: Notebook, isCurrent: Bool, accent: NSColor, scale: CGFloat = 1) {
        self.notebook = notebook
        self.isCurrent = isCurrent
        self.accent = accent
        self.scale = scale
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: (Self.coverSize.width + Self.padding * 2) * scale).isActive = true
        heightAnchor.constraint(equalToConstant: (Self.coverSize.height + Self.padding * 2) * scale).isActive = true
        toolTip = notebook.name
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if event.clickCount == 2 { onDoubleClick?() } else if event.clickCount == 1 { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event.locationInWindow) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        // Draw in unscaled cover coordinates
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        let unscaled = NSRect(x: 0, y: 0, width: bounds.width / scale, height: bounds.height / scale)
        let r = unscaled.insetBy(dx: Self.padding, dy: Self.padding)
        let base = notebook.cover.color
        let coverPath = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)

        if isCurrent {
            let ring = NSBezierPath(roundedRect: r.insetBy(dx: -4.5, dy: -4.5), xRadius: 9, yRadius: 9)
            ring.lineWidth = 2
            accent.setStroke()
            ring.stroke()
        }

        // Cover with a soft drop shadow
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        base.setFill()
        coverPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let elasticX = r.maxX - 22
        let band = NSRect(x: r.minX, y: r.minY + r.height * 0.56, width: r.width, height: r.height * 0.25)

        NSGraphicsContext.saveGraphicsState()
        coverPath.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.08), ending: NSColor.black.withAlphaComponent(0.12))?
            .draw(in: r, angle: -70)
        // Spine
        NSColor.black.withAlphaComponent(0.16).setFill()
        NSRect(x: r.minX, y: r.minY, width: 8, height: r.height).fill()
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: r.minX + 8, y: r.minY, width: 1, height: r.height).fill()
        // Paper label
        NSColor(hex: 0xF4F3EE).setFill()
        band.fill()
        NSColor.black.withAlphaComponent(0.06).setFill()
        NSRect(x: band.minX, y: band.maxY - 1, width: band.width, height: 1).fill()
        // Elastic band over everything
        (base.blended(withFraction: 0.45, of: .black) ?? base).setFill()
        NSRect(x: elasticX, y: r.minY, width: 7, height: r.height).fill()
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSRect(x: elasticX + 1.5, y: r.minY, width: 1, height: r.height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let content = NSRect(x: r.minX + 14, y: r.minY, width: elasticX - r.minX - 22, height: r.height)

        // Embossed emblem
        let emblemY = r.minY + r.height * 0.2
        drawCentered("macnell", in: NSRect(x: content.minX, y: emblemY, width: content.width, height: 16), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.38),
            .kern: 2.2,
        ])
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSRect(x: content.midX - 12, y: emblemY + 21, width: 24, height: 1).fill()

        // Label: title and description
        let title = notebook.name.uppercased()
        let subtitle = notebook.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor(hex: 0x262626),
            .kern: 1.2,
        ]
        let labelArea = NSRect(x: content.minX, y: band.minY, width: content.width, height: band.height)
        if subtitle.isEmpty {
            drawCentered(title, in: NSRect(x: labelArea.minX, y: labelArea.midY - 9, width: labelArea.width, height: 20), attributes: titleAttrs)
        } else {
            drawCentered(title, in: NSRect(x: labelArea.minX, y: labelArea.minY + 11, width: labelArea.width, height: 20), attributes: titleAttrs)
            drawCentered(subtitle, in: NSRect(x: labelArea.minX, y: labelArea.minY + 32, width: labelArea.width, height: labelArea.height - 36), attributes: [
                .font: NSFont.systemFont(ofSize: 10.5),
                .foregroundColor: NSColor(hex: 0x77756F),
            ], lines: 2)
        }

        // Page count, embossed at the bottom
        let count = notebook.pages.count
        drawCentered(count == 1 ? "1 PAGE" : "\(count) PAGES", in: NSRect(x: content.minX, y: r.maxY - 22, width: content.width, height: 14), attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.32),
            .kern: 1.2,
        ])
    }

    private func drawCentered(_ text: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any], lines: Int = 1) {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        var attrs = attributes
        attrs[.paragraphStyle] = p
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}

/// Dashed placeholder cover that creates a notebook
private final class AddCoverView: NSView {
    var onClick: (() -> Void)?
    var tint: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: CoverView.coverSize.width + CoverView.padding * 2).isActive = true
        heightAnchor.constraint(equalToConstant: 84).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func mouseUp(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: CoverView.padding, dy: CoverView.padding)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        path.lineWidth = 1.2
        path.setLineDash([5, 4], count: 2, phase: 0)
        tint.withAlphaComponent(0.5).setStroke()
        path.stroke()
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        ("+  New Notebook" as NSString).draw(with: NSRect(x: r.minX, y: r.midY - 9, width: r.width, height: 18),
                                             options: .usesLineFragmentOrigin,
                                             attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: tint, .paragraphStyle: p])
    }
}

/// ⌘\ shelf of notebook covers
final class CoverShelf: NSObject {
    static let width: CGFloat = 232

    let view = ColorView()

    var onSelect: ((Int) -> Void)?
    var onEdit: ((Int) -> Void)?
    var onContextMenu: ((_ notebook: Int, _ windowPoint: NSPoint) -> Void)?
    var onAdd: (() -> Void)?

    private let store = Store.shared
    private let stack = NSStackView()
    private var theme: Theme = .white

    override init() {
        super.init()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14

        let doc = FlippedView()
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = doc

        // Content keeps a fixed width pinned to the trailing edge so it slides in as the shelf opens
        view.clipsToBounds = true
        for v in [scroll, doc, stack] { v.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll)
        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.widthAnchor.constraint(equalToConstant: Self.width),

            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 48),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -24),
        ])
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        view.color = theme.shelfBackground
        reload()
    }

    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, nb) in store.data.notebooks.enumerated() {
            let cover = CoverView(notebook: nb, isCurrent: i == store.data.currentNotebook, accent: theme.accent)
            cover.onClick = { [weak self] in self?.onSelect?(i) }
            cover.onDoubleClick = { [weak self] in self?.onEdit?(i) }
            cover.onRightClick = { [weak self] point in self?.onContextMenu?(i, point) }
            stack.addArrangedSubview(cover)
        }
        let add = AddCoverView()
        add.tint = theme.secondaryText
        add.onClick = { [weak self] in self?.onAdd?() }
        stack.addArrangedSubview(add)
    }
}

/// Row of cover-color dots used in the cover editor
final class CoverColorPicker: NSView {
    var onChange: ((CoverColor) -> Void)?
    private(set) var selected: CoverColor
    private var dots: [NSButton] = []

    init(selected: CoverColor, ringColor: NSColor) {
        self.selected = selected
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: CGFloat(CoverColor.allCases.count) * 32).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        for (i, cover) in CoverColor.allCases.enumerated() {
            let dot = NSButton(frame: NSRect(x: CGFloat(i) * 32, y: 1, width: 24, height: 24))
            dot.isBordered = false
            dot.title = ""
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 12
            dot.layer?.backgroundColor = cover.color.cgColor
            dot.layer?.borderColor = ringColor.cgColor
            dot.tag = i
            dot.target = self
            dot.action = #selector(pick(_:))
            dot.toolTip = cover.rawValue.capitalized
            addSubview(dot)
            dots.append(dot)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func pick(_ sender: NSButton) {
        selected = CoverColor.allCases[sender.tag]
        refresh()
        onChange?(selected)
    }

    private func refresh() {
        for (i, dot) in dots.enumerated() {
            dot.layer?.borderWidth = CoverColor.allCases[i] == selected ? 3 : 0
        }
    }
}

/// ⌘W "closes" the notebook: the page gives way to its front cover until you open it again
final class ClosedNotebookView: ColorView {
    var onOpen: (() -> Void)?

    private var cover: CoverView?
    private let hint = NSTextField(labelWithString: "Click the cover or press Return to open  ·  ⌘W to close the window")

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        hint.font = .systemFont(ofSize: 12)
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -48),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ notebook: Notebook, theme: Theme) {
        color = theme.background
        hint.textColor = theme.secondaryText.withAlphaComponent(0.7)
        cover?.removeFromSuperview()
        let c = CoverView(notebook: notebook, isCurrent: false, accent: theme.accent, scale: 2.1)
        c.onClick = { [weak self] in self?.onOpen?() }
        c.onDoubleClick = { [weak self] in self?.onOpen?() }
        addSubview(c)
        NSLayoutConstraint.activate([
            c.centerXAnchor.constraint(equalTo: centerXAnchor),
            c.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),
            c.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, constant: -120),
        ])
        cover = c
    }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76, 49: onOpen?()          // Return, Enter, Space
        default: break                      // swallow typing so nothing lands on the hidden page
        }
    }
}
