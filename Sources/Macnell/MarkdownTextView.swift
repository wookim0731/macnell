import AppKit

extension NSAttributedString.Key {
    /// Decorations drawn by the layout manager: "task-off" / "task-on" / "bullet" / "quote"
    static let mnDecoration = NSAttributedString.Key("mnDecoration")
}

/// Text view that keeps the markdown source but renders it live, like Obsidian's live preview.
/// Supports `# / ## / ###` headings, `[]` `[ ]` `[x]` checkboxes (click to toggle), `- ` lists, `> ` quotes
final class MarkdownTextView: NSTextView {
    var theme: Theme = .white {
        didSet {
            markdownLayout?.theme = theme
            insertionPointColor = theme.text
            selectedTextAttributes = [.backgroundColor: theme.accent.withAlphaComponent(0.22)]
            restyle()
        }
    }

    var placeholder = "" { didSet { needsDisplay = true } }

    /// Called when this view gains or loses keyboard focus
    var onFocusChange: (() -> Void)?

    /// Right-click: the app shows its own small menu instead of the system text menu
    var onContextMenu: ((_ windowPoint: NSPoint) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?(event.locationInWindow)
        return nil
    }

    /// Body size from Settings → Text size; everything else scales by `scale`
    static var baseSize: CGFloat { Store.shared.data.textSize.points }
    static var baseFont: NSFont { NSFont.systemFont(ofSize: baseSize) }
    static var scale: CGFloat { baseSize / 15 }

    private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,3})(\\s+)")
    private static let taskRegex = try! NSRegularExpression(pattern: "^(\\s*)((?:[-*+]\\s+)?\\[([ xX]?)\\])(\\s*)")
    private static let bulletRegex = try! NSRegularExpression(pattern: "^(\\s*)([-*+])(\\s+)")
    private static let quoteRegex = try! NSRegularExpression(pattern: "^(>)(\\s?)")

    private var lastActiveParagraph: NSRange?

    private var markdownLayout: MarkdownLayoutManager? { layoutManager as? MarkdownLayoutManager }

    static func makeScrollable() -> (NSScrollView, MarkdownTextView) {
        let storage = NSTextStorage()
        let layout = MarkdownLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.font = baseFont

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        return (scroll, textView)
    }

    // MARK: - Styling

    private var baseParagraph: NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        return p
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Self.baseFont, .foregroundColor: theme.text, .paragraphStyle: baseParagraph]
    }

    func setText(_ text: String) {
        string = text
        lastActiveParagraph = nil
        restyle()
    }

    /// Restyle only when the caret moves to another line (heading markers show on the caret line)
    func selectionMayHaveMovedLine() {
        let active = (string as NSString).paragraphRange(for: selectedRange())
        if active != lastActiveParagraph { restyle() }
    }

    func restyle() {
        // Touching attributes during IME composition (e.g. Korean) breaks input; wait until it commits
        guard let storage = textStorage, !hasMarkedText() else { return }
        let ns = storage.string as NSString
        let active = ns.paragraphRange(for: selectedRange())
        lastActiveParagraph = active

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: ns.length))
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, lineRange, _, _ in
            let isActive = NSIntersectionRange(lineRange, active).length > 0 || lineRange.location == active.location
            self.styleLine(lineRange, in: storage, ns: ns, isActive: isActive)
        }
        storage.endEditing()
        typingAttributes = baseAttributes
    }

    private func styleLine(_ r: NSRange, in s: NSTextStorage, ns: NSString, isActive: Bool) {
        guard r.length > 0 else { return }
        let line = ns.substring(with: r)
        let local = NSRange(location: 0, length: (line as NSString).length)
        func abs(_ x: NSRange) -> NSRange { NSRange(location: x.location + r.location, length: x.length) }

        if let m = Self.headingRegex.firstMatch(in: line, range: local) {
            let level = m.range(at: 1).length
            let size: CGFloat = [26, 21, 17][level - 1] * Self.scale
            let p = baseParagraph
            p.paragraphSpacingBefore = level == 1 ? 8 : 4
            s.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: level == 3 ? .semibold : .bold), .paragraphStyle: p], range: r)
            let marker = abs(m.range)
            if isActive {
                s.addAttribute(.foregroundColor, value: theme.secondaryText, range: marker)
            } else {
                s.addAttributes([.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear], range: marker)
            }
            return
        }

        if let m = Self.taskRegex.firstMatch(in: line, range: local) {
            let marker = abs(m.range(at: 2))
            let inner = (line as NSString).substring(with: m.range(at: 3))
            let checked = inner.lowercased() == "x"
            s.addAttributes([.foregroundColor: NSColor.clear, .mnDecoration: checked ? "task-on" : "task-off"], range: marker)
            widen(marker, to: 30 * Self.scale, in: s)
            if checked {
                let restStart = NSMaxRange(abs(m.range))
                let rest = NSRange(location: restStart, length: NSMaxRange(r) - restStart)
                if rest.length > 0 {
                    s.addAttributes([.foregroundColor: theme.secondaryText, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: rest)
                }
            }
            hangIndent(prefix: abs(m.range), line: r, in: s)
            return
        }

        if let m = Self.bulletRegex.firstMatch(in: line, range: local) {
            let marker = abs(m.range(at: 2))
            s.addAttributes([.foregroundColor: NSColor.clear, .mnDecoration: "bullet"], range: marker)
            widen(marker, to: 12 * Self.scale, in: s)
            hangIndent(prefix: abs(m.range), line: r, in: s)
            return
        }

        if let m = Self.quoteRegex.firstMatch(in: line, range: local) {
            s.addAttributes([.foregroundColor: theme.secondaryText, .mnDecoration: "quote"], range: r)
            let gt = abs(m.range(at: 1))
            s.addAttribute(.foregroundColor, value: NSColor.clear, range: gt)
            widen(gt, to: 16 * Self.scale, in: s)
            hangIndent(prefix: abs(m.range), line: r, in: s)
        }
    }

    /// Pad a hidden marker to a minimum width by kerning its last character
    private func widen(_ range: NSRange, to width: CGFloat, in s: NSTextStorage) {
        let current = s.attributedSubstring(from: range).size().width
        guard current < width, range.length > 0 else { return }
        s.addAttribute(.kern, value: width - current, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
    }

    /// Align wrapped lines with the text after the marker
    private func hangIndent(prefix: NSRange, line: NSRange, in s: NSTextStorage) {
        let p = baseParagraph
        p.headIndent = s.attributedSubstring(from: prefix).size().width
        s.addAttribute(.paragraphStyle, value: p, range: line)
    }

    // MARK: - Checkbox clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let range = taskMarker(at: point) {
            toggleTask(in: range)
            return
        }
        super.mouseDown(with: event)
    }

    private func taskMarker(at point: NSPoint) -> NSRange? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: p, in: container, fractionOfDistanceThroughGlyph: nil)
        let char = layout.characterIndexForGlyph(at: glyph)
        guard char < storage.length else { return nil }
        var effective = NSRange()
        guard let kind = storage.attribute(.mnDecoration, at: char, effectiveRange: &effective) as? String,
              kind.hasPrefix("task") else { return nil }
        let rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: effective, actualCharacterRange: nil), in: container)
        return rect.insetBy(dx: -2, dy: -2).contains(p) ? effective : nil
    }

    private func toggleTask(in marker: NSRange) {
        let ns = string as NSString
        let text = ns.substring(with: marker)
        guard let open = text.firstIndex(of: "[") else { return }
        let openOffset = (String(text[..<open]) as NSString).length
        let innerLocation = marker.location + openOffset + 1
        let replaceRange: NSRange
        let replacement: String
        switch ns.substring(with: NSRange(location: innerLocation, length: 1)) {
        case "]": replaceRange = NSRange(location: innerLocation, length: 0); replacement = "x"
        case " ": replaceRange = NSRange(location: innerLocation, length: 1); replacement = "x"
        default: replaceRange = NSRange(location: innerLocation, length: 1); replacement = " "
        }
        if shouldChangeText(in: replaceRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: replaceRange, with: replacement)
            didChangeText()
        }
    }

    // MARK: - Continue lists on Return

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        var lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        if lineRange.length > 0, ns.substring(with: NSRange(location: NSMaxRange(lineRange) - 1, length: 1)) == "\n" {
            lineRange.length -= 1
        }
        let line = ns.substring(with: lineRange)
        let local = NSRange(location: 0, length: (line as NSString).length)

        var prefix: String?
        var matched = NSRange()
        if let m = Self.taskRegex.firstMatch(in: line, range: local) {
            let lead = (line as NSString).substring(with: m.range(at: 1))
            let hasDash = (line as NSString).substring(with: m.range(at: 2)).first.map { "-*+".contains($0) } ?? false
            prefix = lead + (hasDash ? "- " : "") + "[ ] "
            matched = m.range
        } else if let m = Self.bulletRegex.firstMatch(in: line, range: local) {
            prefix = (line as NSString).substring(with: m.range(at: 1)) + (line as NSString).substring(with: m.range(at: 2)) + " "
            matched = m.range
        } else if let m = Self.quoteRegex.firstMatch(in: line, range: local) {
            prefix = "> "
            matched = m.range
        }

        guard let prefix, sel.location >= lineRange.location + matched.length else {
            super.insertNewline(sender)
            return
        }
        if NSMaxRange(matched) >= local.length {
            // Return on an empty item ends the list
            insertText("", replacementRange: lineRange)
        } else {
            insertText("\n" + prefix, replacementRange: sel)
        }
    }

    // MARK: - Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, isEditable else { return }
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: Self.baseFont,
            .foregroundColor: theme.secondaryText.withAlphaComponent(0.6),
        ])
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        DispatchQueue.main.async { self.onFocusChange?() }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        DispatchQueue.main.async { self.onFocusChange?() }
        return ok
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

/// Draws checkboxes, bullets and quote bars where the hidden markers are
final class MarkdownLayoutManager: NSLayoutManager {
    var theme: Theme = .white

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let font = MarkdownTextView.baseFont

        storage.enumerateAttribute(.mnDecoration, in: chars) { value, range, _ in
            guard let kind = value as? String else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let rect = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = origin.y + fragment.minY + location(forGlyphAt: glyphs.location).y

            switch kind {
            case "task-off", "task-on":
                let size: CGFloat = 14 * MarkdownTextView.scale
                let box = NSRect(x: rect.minX + 2, y: baseline - font.capHeight / 2 - size / 2, width: size, height: size)
                let path = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
                if kind == "task-on" {
                    theme.accent.setFill()
                    path.fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: box.minX + 3.2, y: box.midY + 0.2))
                    check.line(to: NSPoint(x: box.minX + 6, y: box.maxY - 3.6))
                    check.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 3.6))
                    check.lineWidth = 1.8
                    check.lineCapStyle = .round
                    check.lineJoinStyle = .round
                    NSColor.white.setStroke()
                    check.stroke()
                } else {
                    path.lineWidth = 1.3
                    theme.secondaryText.setStroke()
                    path.stroke()
                }
            case "bullet":
                let r: CGFloat = 2.6 * MarkdownTextView.scale
                let center = NSPoint(x: rect.minX + 5 * MarkdownTextView.scale, y: baseline - font.xHeight / 2)
                theme.text.setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)).fill()
            case "quote":
                theme.divider.setFill()
                enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, _, _ in
                    NSRect(x: rect.minX + 1, y: origin.y + lineRect.minY, width: 3, height: lineRect.height).fill()
                }
            default:
                break
            }
        }
    }
}
