import AppKit

/// Rounded text button in the app's own style
final class ThemedButton: NSButton {
    enum Style { case primary, plain, destructive }

    private let style: Style
    private let theme: Theme
    private let handler: () -> Void
    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    init(_ title: String, style: Style, theme: Theme, handler: @escaping () -> Void) {
        self.style = style
        self.theme = theme
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }

    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: Self.titleFont]).width
        return NSSize(width: ceil(w) + 32, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let (fill, text): (NSColor, NSColor) = switch style {
        case .primary: (theme.text, theme.background)
        case .plain: (theme.text.withAlphaComponent(0.07), theme.text)
        case .destructive: (Theme.danger, .white)
        }
        (isHighlighted ? fill.withAlphaComponent(fill.alphaComponent * 0.75) : fill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        (title as NSString).draw(with: NSRect(x: 0, y: (bounds.height - 17) / 2, width: bounds.width, height: 17),
                                 options: .usesLineFragmentOrigin,
                                 attributes: [.font: Self.titleFont, .foregroundColor: text, .paragraphStyle: p])
    }
}

/// Floating surface for dialogs and menus; swallows clicks so they don't reach the scrim
final class CardView: ColorView {
    init(theme: Theme, radius: CGFloat = 12) {
        super.init(frame: .zero)
        color = theme.surface
        layer?.cornerRadius = radius
        layer?.borderWidth = 1
        layer?.borderColor = theme.text.withAlphaComponent(0.08).cgColor
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(theme == .black ? 0.5 : 0.18)
            s.shadowBlurRadius = 24
            s.shadowOffset = NSSize(width: 0, height: -6)
            return s
        }()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

/// Full-window layer behind a card: click outside or Esc dismisses, Return confirms
final class OverlayView: NSView {
    var onDismiss: (() -> Void)?
    var onConfirm: (() -> Void)?

    init(dimmed: Bool, theme: Theme) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = dimmed ? NSColor.black.withAlphaComponent(theme == .black ? 0.45 : 0.16).cgColor : NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { onDismiss?() }
    override func rightMouseDown(with event: NSEvent) { onDismiss?() }
    override func scrollWheel(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onDismiss?()               // Esc
        case 36, 76: onConfirm?()           // Return / Enter
        default: super.keyDown(with: event)
        }
    }
}

/// One row of a themed context menu
final class MenuRow: NSView {
    private let handler: () -> Void
    private let hoverColor: NSColor
    private var hovering = false { didSet { needsDisplay = true } }

    init(_ title: String, destructive: Bool, theme: Theme, handler: @escaping () -> Void) {
        self.handler = handler
        hoverColor = theme.text.withAlphaComponent(0.07)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = destructive ? Theme.danger : theme.text
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
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
    override func mouseUp(with event: NSEvent) { handler() }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        hoverColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
}

/// Text field sitting on a soft rounded well
func makeThemedField(_ value: String, placeholder: String, theme: Theme) -> (container: NSView, field: NSTextField) {
    let well = ColorView()
    well.color = theme.text.withAlphaComponent(0.05)
    well.layer?.cornerRadius = 7
    let field = NSTextField(string: value)
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 14)
    field.textColor = theme.text
    field.cell?.isScrollable = true
    field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
        .font: NSFont.systemFont(ofSize: 14), .foregroundColor: theme.secondaryText.withAlphaComponent(0.7),
    ])
    for v in [well, field] { v.translatesAutoresizingMaskIntoConstraints = false }
    well.addSubview(field)
    NSLayoutConstraint.activate([
        well.heightAnchor.constraint(equalToConstant: 34),
        field.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 10),
        field.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -10),
        field.centerYAnchor.constraint(equalTo: well.centerYAnchor),
    ])
    return (well, field)
}

/// Small caption above a field
func makeCaption(_ text: String, theme: Theme) -> NSTextField {
    let l = NSTextField(labelWithString: text.uppercased())
    l.font = .systemFont(ofSize: 10, weight: .semibold)
    l.textColor = theme.secondaryText
    return l
}

/// Row of pill-shaped options, one selected (e.g. page layout)
final class PillPicker: NSView {
    var onChange: ((Int) -> Void)?
    private(set) var selected: Int
    private let options: [String]
    private let theme: Theme
    private var rects: [NSRect] = []
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    init(options: [String], selected: Int, theme: Theme) {
        self.options = options
        self.selected = selected
        self.theme = theme
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        var x: CGFloat = 0
        for option in options {
            let w = ceil((option as NSString).size(withAttributes: [.font: Self.font]).width) + 24
            rects.append(NSRect(x: x, y: 0, width: w, height: 26))
            x += w + 6
        }
        widthAnchor.constraint(equalToConstant: max(0, x - 6)).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = rects.firstIndex(where: { $0.contains(p) }), i != selected else { return }
        selected = i
        needsDisplay = true
        onChange?(i)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        for (i, rect) in rects.enumerated() {
            let on = i == selected
            (on ? theme.text : theme.text.withAlphaComponent(0.06)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
            (options[i] as NSString).draw(with: NSRect(x: rect.minX, y: (rect.height - 16) / 2, width: rect.width, height: 16),
                                          options: .usesLineFragmentOrigin,
                                          attributes: [.font: Self.font, .paragraphStyle: p,
                                                       .foregroundColor: on ? theme.background : theme.text])
        }
    }
}
