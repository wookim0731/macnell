import AppKit

/// Solid-color view (rules, backgrounds)
class ColorView: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = color.cgColor }
}

/// Thin chevron beside the page that flips to the previous / next page; faint until hovered
final class PageArrow: NSView {
    enum Direction { case previous, next }

    var onClick: (() -> Void)?
    var color: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }

    private let direction: Direction
    private var hovering = false { didSet { needsDisplay = true } }

    init(_ direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: 72).isActive = true
        toolTip = direction == .previous ? "Previous page (⇧⌘[)" : "Next page (⇧⌘])"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let w: CGFloat = 9, h: CGFloat = 22
        let x = direction == .previous ? bounds.midX + w / 2 : bounds.midX - w / 2
        let tip = direction == .previous ? bounds.midX - w / 2 : bounds.midX + w / 2
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: x, y: bounds.midY + h / 2))
        chevron.line(to: NSPoint(x: tip, y: bounds.midY))
        chevron.line(to: NSPoint(x: x, y: bounds.midY - h / 2))
        chevron.lineWidth = 1.6
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        color.withAlphaComponent(hovering ? 0.9 : 0.35).setStroke()
        chevron.stroke()
    }
}

/// Section title; in the Macnell layout a double-click turns it into a field for renaming the section
private final class SectionLabel: NSTextField {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if !isEditable, event.clickCount == 2, let onDoubleClick { onDoubleClick() } else { super.mouseDown(with: event) }
    }
}

/// One page: title/date header plus up to three sections arranged by the notebook's layout.
///
/// | stored field | Macnell | Cornell          | Blank  |
/// |--------------|---------|------------------|--------|
/// | `cue`        | To Do   | Cues (left)      | hidden |
/// | `notes`      | Done    | Notes (right)    | Notes  |
/// | `summary`    | Summary | Summary (bottom) | hidden |
///
/// Macnell section titles belong to the notebook; double-click one to rename it.
final class PageView: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    var onEdit: ((Page) -> Void)?
    var onContextMenu: ((_ textView: MarkdownTextView, _ windowPoint: NSPoint) -> Void)?
    var onRenameSection: ((_ index: Int, _ name: String) -> Void)?

    private(set) var page = Page()
    private var loading = false

    private let titleField = NSTextField()
    private let dateLabel = NSTextField(labelWithString: "")
    private let firstLabel = SectionLabel(labelWithString: "")
    private let bodyLabel = SectionLabel(labelWithString: "")
    private let lastLabel = SectionLabel(labelWithString: "")
    private var sectionNames = Notebook.defaultSectionNames
    private var renaming: (label: SectionLabel, index: Int, minWidth: NSLayoutConstraint)?
    private let headerLine = ColorView()
    private let splitLine = ColorView()     // vertical in Cornell, horizontal in Macnell
    private let lastLine = ColorView()

    private let firstScroll: NSScrollView, first: MarkdownTextView
    private let bodyScroll: NSScrollView, body: MarkdownTextView
    private let lastScroll: NSScrollView, last: MarkdownTextView

    private var layoutKind: PageLayout?
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var position = (index: 0, count: 1)
    /// Where the caret was on each page this session, so flipping back lands in the same spot
    private var cursors: [UUID: Cursor] = [:]
    private struct Cursor {
        var focused: Int?                       // 0 title, 1...3 sections
        var selections: [NSRange]               // first, body, last
        var scrolls: [NSPoint]
    }
    private var showsEmpty = false
    private var theme: Theme = .white

    private let m: CGFloat = 32

    /// Read-only pages (the left page of the two-page view) can be read and selected but not edited
    var isReadOnly = false {
        didSet {
            titleField.isEditable = !isReadOnly
            for tv in [first, body, last] { tv.isEditable = !isReadOnly }
        }
    }

    override init(frame: NSRect) {
        (firstScroll, first) = MarkdownTextView.makeScrollable()
        (bodyScroll, body) = MarkdownTextView.makeScrollable()
        (lastScroll, last) = MarkdownTextView.makeScrollable()
        super.init(frame: frame)

        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.placeholderString = "Untitled"
        titleField.delegate = self
        titleField.cell?.lineBreakMode = .byTruncatingTail

        dateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        for (i, label) in [firstLabel, bodyLabel, lastLabel].enumerated() {
            label.delegate = self
            label.focusRingType = .none
            label.onDoubleClick = { [weak self] in self?.beginRenaming(i) }
        }
        for tv in [first, body, last] {
            tv.delegate = self
            tv.onFocusChange = { [weak self] in self?.updateSectionLabels() }
            tv.onContextMenu = { [weak self, weak tv] point in
                if let tv { self?.onContextMenu?(tv, point) }
            }
        }

        let views: [NSView] = [titleField, dateLabel, headerLine, firstLabel, bodyLabel, lastLabel,
                               firstScroll, splitLine, bodyScroll, lastLine, lastScroll]
        for v in views {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -16),
            dateLabel.firstBaselineAnchor.constraint(equalTo: titleField.firstBaselineAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -m),

            headerLine.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),
            headerLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m - 8),
            headerLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(m - 8)),
            headerLine.heightAnchor.constraint(equalToConstant: 1),
        ])
        setLayout(.macnell)
        applyTextSize()
    }

    /// Re-apply Settings → Text size to the title and every section
    func applyTextSize() {
        titleField.font = .systemFont(ofSize: 24 * MarkdownTextView.scale, weight: .bold)
        let labelFont = NSFont.systemFont(ofSize: 12 * MarkdownTextView.scale, weight: .semibold)
        for label in [firstLabel, bodyLabel, lastLabel] { label.font = labelFont }
        updateSectionLabels()
        for tv in [first, body, last] {
            tv.font = MarkdownTextView.baseFont
            tv.restyle()
            tv.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layouts

    func setLayout(_ kind: PageLayout) {
        guard kind != layoutKind else { return }
        layoutKind = kind
        NSLayoutConstraint.deactivate(layoutConstraints)
        let all: [NSView] = [firstLabel, firstScroll, splitLine, bodyLabel, bodyScroll, lastLine, lastLabel, lastScroll]
        all.forEach { $0.isHidden = false }

        switch kind {
        case .macnell:
            setSections(sectionNames[0], sectionNames[1], sectionNames[2])
            layoutConstraints = stacked(firstHeight: 0.26) + lastSection()
        case .cornell:
            setSections("CUES", "NOTES", "SUMMARY")
            layoutConstraints = columns() + lastSection()
        case .blank:
            setSections("", "", "")
            [firstLabel, firstScroll, splitLine, bodyLabel, lastLine, lastLabel, lastScroll].forEach { $0.isHidden = true }
            layoutConstraints = [
                bodyScroll.topAnchor.constraint(equalTo: headerLine.bottomAnchor, constant: 14),
                bodyScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m - 9),
                bodyScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(m - 9)),
                bodyScroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            ]
        }
        NSLayoutConstraint.activate(layoutConstraints)
        updateSectionLabels()
    }

    /// The notebook's Macnell section titles
    func setSectionNames(_ names: [String]) {
        guard names != sectionNames else { return }
        sectionNames = names
        guard layoutKind == .macnell, renaming == nil else { return }
        setSections(names[0], names[1], names[2])
        updateSectionLabels()
    }

    private func beginRenaming(_ index: Int) {
        guard layoutKind == .macnell, !isReadOnly, !showsEmpty, renaming == nil else { return }
        let label = [firstLabel, bodyLabel, lastLabel][index]
        let minWidth = label.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        minWidth.isActive = true
        renaming = (label, index, minWidth)
        label.isEditable = true
        label.textColor = theme.text
        label.stringValue = sectionNames[index]
        label.placeholderString = Notebook.defaultSectionNames[index]
        window?.makeFirstResponder(label)
        label.currentEditor()?.selectAll(nil)
    }

    /// Ends a rename; `save` false (Escape) keeps the old title.
    /// Return and Escape continue in that section; a click elsewhere leaves focus where it went.
    private func endRenaming(save: Bool, focusSection: Bool) {
        guard let (label, index, minWidth) = renaming else { return }
        renaming = nil
        let name = label.stringValue
        label.abortEditing()
        minWidth.isActive = false
        label.isEditable = false
        label.placeholderString = nil
        label.stringValue = sectionNames[index]
        if save { onRenameSection?(index, name) }
        if focusSection { window?.makeFirstResponder([first, body, last][index]) }
        updateSectionLabels()
    }

    /// Section labels; every empty section shows a plain "…"
    private func setSections(_ firstTitle: String, _ bodyTitle: String, _ lastTitle: String) {
        firstLabel.stringValue = firstTitle
        bodyLabel.stringValue = bodyTitle
        lastLabel.stringValue = lastTitle
        for tv in [first, body, last] { tv.placeholder = "…" }
    }

    /// Macnell: To Do / Done / Summary stacked top to bottom
    private func stacked(firstHeight: CGFloat) -> [NSLayoutConstraint] {
        [
            firstLabel.topAnchor.constraint(equalTo: headerLine.bottomAnchor, constant: 14),
            firstLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m),
            firstScroll.topAnchor.constraint(equalTo: firstLabel.bottomAnchor, constant: 6),
            firstScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m - 9),
            firstScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(m - 9)),
            firstScroll.heightAnchor.constraint(equalTo: heightAnchor, multiplier: firstHeight),

            splitLine.topAnchor.constraint(equalTo: firstScroll.bottomAnchor, constant: 10),
            splitLine.leadingAnchor.constraint(equalTo: headerLine.leadingAnchor),
            splitLine.trailingAnchor.constraint(equalTo: headerLine.trailingAnchor),
            splitLine.heightAnchor.constraint(equalToConstant: 1),

            bodyLabel.topAnchor.constraint(equalTo: splitLine.bottomAnchor, constant: 14),
            bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m),
            bodyScroll.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 6),
            bodyScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m - 9),
            bodyScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(m - 9)),
            bodyScroll.bottomAnchor.constraint(equalTo: lastLine.topAnchor, constant: -10),
        ]
    }

    /// Cornell: narrow cue column on the left, notes on the right
    private func columns() -> [NSLayoutConstraint] {
        [
            firstLabel.topAnchor.constraint(equalTo: headerLine.bottomAnchor, constant: 14),
            firstLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m),
            firstScroll.topAnchor.constraint(equalTo: firstLabel.bottomAnchor, constant: 6),
            firstScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m - 9),
            firstScroll.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.28),
            firstScroll.bottomAnchor.constraint(equalTo: lastLine.topAnchor, constant: -10),

            splitLine.topAnchor.constraint(equalTo: headerLine.bottomAnchor),
            splitLine.bottomAnchor.constraint(equalTo: lastLine.topAnchor),
            splitLine.leadingAnchor.constraint(equalTo: firstScroll.trailingAnchor, constant: 10),
            splitLine.widthAnchor.constraint(equalToConstant: 1),

            bodyLabel.topAnchor.constraint(equalTo: firstLabel.topAnchor),
            bodyLabel.leadingAnchor.constraint(equalTo: splitLine.trailingAnchor, constant: 20),
            bodyScroll.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 6),
            bodyScroll.leadingAnchor.constraint(equalTo: splitLine.trailingAnchor, constant: 11),
            bodyScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(m - 9)),
            bodyScroll.bottomAnchor.constraint(equalTo: firstScroll.bottomAnchor),
        ]
    }

    /// Bottom section shared by Macnell and Cornell
    private func lastSection() -> [NSLayoutConstraint] {
        [
            lastLine.leadingAnchor.constraint(equalTo: headerLine.leadingAnchor),
            lastLine.trailingAnchor.constraint(equalTo: headerLine.trailingAnchor),
            lastLine.heightAnchor.constraint(equalToConstant: 1),

            lastLabel.topAnchor.constraint(equalTo: lastLine.bottomAnchor, constant: 14),
            lastLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m),
            lastScroll.topAnchor.constraint(equalTo: lastLabel.bottomAnchor, constant: 6),
            lastScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m - 9),
            lastScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(m - 9)),
            lastScroll.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.18),
            lastScroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ]
    }

    /// Sections in reading order for the current layout
    private var sections: [MarkdownTextView] {
        layoutKind == .blank ? [body] : [first, body, last]
    }

    /// Where typing starts: To Do in Macnell, the notes body otherwise
    private var primary: MarkdownTextView {
        layoutKind == .macnell ? first : body
    }

    // MARK: - Content

    func load(_ page: Page, index: Int, count: Int) {
        if !isReadOnly, !showsEmpty { rememberCursor() }
        loading = true
        self.page = page
        showsEmpty = false
        titleField.placeholderString = "Untitled"
        titleField.stringValue = page.title
        position = (index, count)
        refreshDate()
        first.setText(page.cue)
        body.setText(page.notes)
        last.setText(page.summary)
        let saved = cursors[page.id]
        for (i, tv) in [first, body, last].enumerated() {
            let length = (tv.string as NSString).length
            if let saved, NSMaxRange(saved.selections[i]) <= length {
                tv.setSelectedRange(saved.selections[i])
                tv.scroll(saved.scrolls[i])
            } else {
                tv.setSelectedRange(NSRange(location: length, length: 0))
                tv.scroll(.zero)
            }
        }
        // Don't let ⌘Z undo into another page's text
        window?.undoManager?.removeAllActions()
        loading = false
    }

    /// Empty read-only page with a faint message in the title spot
    func loadEmpty(message: String) {
        loading = true
        page = Page()
        showsEmpty = true
        titleField.stringValue = ""
        titleField.placeholderString = message
        dateLabel.stringValue = ""
        for tv in [first, body, last] { tv.setText("") }
        loading = false
    }

    /// Re-render the date line (date format may have changed in Settings)
    func refreshDate() {
        guard !showsEmpty else { return }
        let date = Store.shared.data.dateStyle.string(from: page.created)
        dateLabel.stringValue = "\(date)   \(position.index + 1) / \(position.count)"
    }

    func focusTitle() {
        window?.makeFirstResponder(titleField)
    }

    func focusPrimary() {
        window?.makeFirstResponder(primary)
    }

    /// Back where the caret was when this page was last left; the primary section on a first visit
    func focusRemembered() {
        let views: [NSView] = [titleField, first, body, last]
        if let i = cursors[page.id]?.focused, sections.contains(where: { $0 === views[i] }) || i == 0 {
            window?.makeFirstResponder(views[i])
            // The title would otherwise come back fully selected
            if i == 0 { titleField.currentEditor()?.selectedRange = NSRange(location: (titleField.stringValue as NSString).length, length: 0) }
        } else {
            focusPrimary()
        }
    }

    private func rememberCursor() {
        let views: [NSView] = [titleField, first, body, last]
        let active = activeSection
        cursors[page.id] = Cursor(focused: views.firstIndex { $0 === active },
                                  selections: [first, body, last].map { $0.selectedRange() },
                                  scrolls: [first, body, last].map { $0.enclosingScrollView?.contentView.bounds.origin ?? .zero })
    }

    /// ⌘] / ⌘[ : cycle the title and the visible sections
    func moveSection(by offset: Int) {
        let order: [NSView] = [titleField] + sections
        let current = order.firstIndex { $0 === activeSection } ?? (order.firstIndex { $0 === primary } ?? 0)
        window?.makeFirstResponder(order[(current + offset + order.count) % order.count])
        updateSectionLabels()
    }

    private var activeSection: NSView? {
        let responder = window?.firstResponder
        if let tv = responder as? MarkdownTextView { return tv }
        if let editor = responder as? NSTextView, editor.isFieldEditor, (editor.delegate as AnyObject?) === titleField { return titleField }
        return nil
    }

    /// The focused section's label goes dark so you can see where you are
    private func updateSectionLabels() {
        let active = activeSection
        for (label, tv) in [(firstLabel, first), (bodyLabel, body), (lastLabel, last)] where label !== renaming?.label {
            label.attributedStringValue = NSAttributedString(string: label.stringValue, attributes: [
                .font: label.font ?? NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: tv === active ? theme.text : theme.secondaryText.withAlphaComponent(0.8),
                .kern: 0.8,
            ])
        }
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        titleField.textColor = theme.text
        dateLabel.textColor = theme.secondaryText
        updateSectionLabels()
        headerLine.color = theme.divider
        splitLine.color = theme.divider
        lastLine.color = theme.divider
        for tv in [first, body, last] { tv.theme = theme }
    }

    // MARK: - Edits

    func textDidChange(_ notification: Notification) {
        guard !loading, let tv = notification.object as? MarkdownTextView else { return }
        tv.restyle()
        switch tv {
        case first: page.cue = tv.string
        case body: page.notes = tv.string
        default: page.summary = tv.string
        }
        commit()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        (notification.object as? MarkdownTextView)?.selectionMayHaveMovedLine()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !loading, obj.object as? NSTextField === titleField else { return }
        page.title = titleField.stringValue
        commit()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let renaming, obj.object as? NSTextField === renaming.label {
            let movement = obj.userInfo?["NSTextMovement"] as? Int
            endRenaming(save: true, focusSection: movement == NSTextMovement.return.rawValue)
            return
        }
        // Return in the title moves to where you start writing
        if (obj.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.return.rawValue { focusPrimary() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(cancelOperation(_:)), control === renaming?.label else { return false }
        endRenaming(save: false, focusSection: true)
        return true
    }

    private func commit() {
        page.modified = Date()
        onEdit?(page)
    }
}
