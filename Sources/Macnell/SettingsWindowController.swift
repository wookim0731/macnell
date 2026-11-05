import AppKit
import ServiceManagement

/// Paper-color swatch with its name underneath
final class SwatchButton: NSButton {
    let theme: Theme
    var isChosen = false { didSet { needsDisplay = true } }

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 62))
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightAnchor.constraint(equalToConstant: 62).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let swatch = NSRect(x: 6, y: bounds.maxY - 44, width: bounds.width - 12, height: 40)
        let path = NSBezierPath(roundedRect: swatch, xRadius: 7, yRadius: 7)
        theme.background.setFill()
        path.fill()
        if isChosen {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2.5
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        let label = theme.label as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: isChosen ? .semibold : .regular),
            .foregroundColor: isChosen ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 0), withAttributes: attrs)
    }

    override var isFlipped: Bool { false }
}

/// ⌘, settings, grouped into Appearance / Pages / General, plus a list of every shortcut
final class SettingsWindowController: NSObject, NSWindowDelegate {
    var onThemeChange: ((Theme) -> Void)?
    var onDateStyleChange: (() -> Void)?
    var onTwoPageViewChange: ((Bool) -> Void)?
    var onReopenChange: ((_ showsCover: Bool) -> Void)?
    var onMenuBarIconChange: ((Bool) -> Void)?
    var onTextSizeChange: ((TextSize) -> Void)?

    /// Every shortcut in the app, shown in Settings so nothing is hidden
    static let shortcuts: [(keys: String, action: String)] = [
        ("⌘W", "Close the notebook (shows its cover); press again to close the window"),
        ("⇧⌘[ / ⇧⌘]", "Previous / next page (or swipe with two fingers, or the arrows beside the page)"),
        ("⌘T", "New page"),
        ("⌘[ / ⌘]", "Move between title and sections"),
        ("⌘\\", "Show or hide notebook covers"),
        ("⌃⌘F", "Leave full screen for a while (it comes back next time you open Macnell)"),
        ("⇧⌘N", "New notebook"),
        ("⌘,", "Settings"),
    ]

    private var window: NSWindow?
    private var swatches: [SwatchButton] = []
    private let datePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pageModeControl = NSSegmentedControl(labels: ["One page", "Two pages"], trackingMode: .selectOne, target: nil, action: nil)
    private let textSizeControl = NSSegmentedControl(labels: TextSize.allCases.map(\.label), trackingMode: .selectOne, target: nil, action: nil)
    private let reopenControl = NSSegmentedControl(labels: ["Last page", "Cover"], trackingMode: .selectOne, target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch Macnell at login", target: nil, action: nil)
    private let menuBarCheckbox = NSButton(checkboxWithTitle: "Show icon in the menu bar", target: nil, action: nil)

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Re-read every value
    func refresh() {
        let data = Store.shared.data
        for s in swatches { s.isChosen = s.theme == data.theme }
        datePopup.removeAllItems()
        for style in DateStyle.allCases {
            datePopup.addItem(withTitle: style.string(from: Date()))
        }
        datePopup.selectItem(at: DateStyle.allCases.firstIndex(of: data.dateStyle) ?? 0)
        pageModeControl.selectedSegment = data.twoPageView ? 1 : 0
        reopenControl.selectedSegment = data.reopenShowsCover ? 1 : 0
        textSizeControl.selectedSegment = TextSize.allCases.firstIndex(of: data.textSize) ?? 1
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menuBarCheckbox.state = data.showsMenuBarIcon ? .on : .off
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        // Show on top of the full-screen notes space instead of jumping to another desktop
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.level = .floating

        swatches = Theme.allCases.map { theme in
            let s = SwatchButton(theme: theme)
            s.target = self
            s.action = #selector(pickTheme(_:))
            return s
        }
        let swatchRow = NSStackView(views: swatches)
        swatchRow.spacing = 8
        swatchRow.setHuggingPriority(.required, for: .vertical)  // window fits the grid instead of stretching this row

        datePopup.target = self
        datePopup.action = #selector(pickDateStyle)
        pageModeControl.target = self
        pageModeControl.action = #selector(pickPageMode)
        textSizeControl.target = self
        textSizeControl.action = #selector(pickTextSize)
        reopenControl.target = self
        reopenControl.action = #selector(pickReopen)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLaunchAtLogin)
        menuBarCheckbox.target = self
        menuBarCheckbox.action = #selector(toggleMenuBarIcon)

        var rows: [[NSView]] = []
        var headerRows: [Int] = []
        func header(_ title: String) {
            headerRows.append(rows.count)
            let l = NSTextField(labelWithString: title.uppercased())
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            rows.append([l, NSGridCell.emptyContentView])
        }
        func row(_ label: String, _ control: NSView, hint: String? = nil) {
            let l = NSTextField(labelWithString: label)
            l.alignment = .right
            if let hint {
                let stack = NSStackView(views: [control, Self.hint(hint)])
                stack.orientation = .vertical
                stack.alignment = .leading
                stack.spacing = 6
                rows.append([l, stack])
            } else {
                rows.append([l, control])
            }
        }

        header("Appearance")
        row("Paper:", swatchRow)
        row("Text size:", textSizeControl)
        row("Date:", datePopup, hint: "How dates appear at the top of each page.")

        header("Pages")
        row("Page view:", pageModeControl,
            hint: "Two pages shows the previous page on the left (read-only) next to the one you're writing in.")
        row("Reopen to:", reopenControl,
            hint: "What you see when you come back after closing the window (⌘W twice).")
        row("Layout:", Self.hint("Each notebook has its own layout: Macnell (To Do / Done / Summary), Cornell or Blank. Open the covers with ⌘\\ and double-click one to change it. In Macnell, double-click a section title on the page to rename it for that notebook."))

        header("General")
        row("Startup:", loginCheckbox)
        row("Menu bar:", menuBarCheckbox,
            hint: "Without the icon, open Macnell from Launchpad or Finder, or swipe to its space.")

        header("Shortcuts")
        for (keys, action) in Self.shortcuts {
            let k = NSTextField(labelWithString: keys)
            k.font = .systemFont(ofSize: 13, weight: .medium)
            k.alignment = .right
            let a = NSTextField(labelWithString: action)
            a.textColor = .secondaryLabelColor
            rows.append([k, a])
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 110
        grid.rowAlignment = .firstBaseline
        let swatchGridRow = grid.row(at: headerRows[0] + 1)
        swatchGridRow.rowAlignment = .none
        swatchGridRow.yPlacement = .top
        for h in headerRows {
            grid.row(at: h).mergeCells(in: NSRange(location: 0, length: 2))
            grid.cell(atColumnIndex: 0, rowIndex: h).xPlacement = .leading
            if h > 0 { grid.row(at: h).topPadding = 14 }
        }
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
        ])
        window.contentView = content
        return window
    }

    private static func hint(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 340
        return l
    }

    @objc private func pickTheme(_ sender: SwatchButton) {
        onThemeChange?(sender.theme)
        refresh()
    }

    @objc private func pickDateStyle() {
        Store.shared.data.dateStyle = DateStyle.allCases[max(0, datePopup.indexOfSelectedItem)]
        onDateStyleChange?()
    }

    @objc private func pickPageMode() {
        onTwoPageViewChange?(pageModeControl.selectedSegment == 1)
    }

    @objc private func pickTextSize() {
        onTextSizeChange?(TextSize.allCases[max(0, textSizeControl.selectedSegment)])
    }

    @objc private func pickReopen() {
        onReopenChange?(reopenControl.selectedSegment == 1)
    }

    @objc private func toggleMenuBarIcon() {
        onMenuBarIconChange?(menuBarCheckbox.state == .on)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = "\(error.localizedDescription)\nMove Macnell to the Applications folder and try again."
            if let window { alert.beginSheetModal(for: window) }
        }
        refresh()
    }
}
