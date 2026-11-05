import AppKit
import QuartzCore

final class MainWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow

    private let store = Store.shared
    private let root = ColorView()
    private let pageHost = ColorView()
    private let pageView = PageView()
    private let previousView = PageView()     // left page in the two-page view
    private let gutter = ColorView()
    private var singleConstraints: [NSLayoutConstraint] = []
    private var spreadConstraints: [NSLayoutConstraint] = []
    private var maxPageWidth: NSLayoutConstraint!
    private let shelf = CoverShelf()
    private let closedView = ClosedNotebookView()
    private var isClosed: Bool { !closedView.isHidden }
    private var shelfWidth: NSLayoutConstraint!
    private var shelfVisible = false

    private var overlay: OverlayView?
    private var scrollMonitor: Any?

    // Horizontal swipe tracking
    private enum Axis { case undecided, horizontal, vertical }
    private var swipeAxis = Axis.undecided
    private var swipeAccum: CGFloat = 0
    private var swipeFired = false
    private var lastWheelTime: TimeInterval = 0

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Macnell"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 520)
        window.delegate = self
        window.center()

        buildLayout()
        pageView.onEdit = { [weak self] page in self?.store.page = page }
        shelf.onSelect = { [weak self] n in self?.selectNotebook(n) }
        shelf.onEdit = { [weak self] n in self?.editCover(n) }
        shelf.onContextMenu = { [weak self] n, point in self?.showCoverMenu(n, at: point) }
        shelf.onAdd = { [weak self] in self?.addNotebook() }
        closedView.onOpen = { [weak self] in self?.openNotebook() }
        applyTheme()
        applyPageMode()
        showCurrentPage(direction: 0)
        installSwipeMonitor()
    }

    // MARK: - Layout

    private func buildLayout() {
        window.contentView = root

        pageHost.wantsLayer = true
        shelf.view.isHidden = true
        for v in [shelf.view, pageHost] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        previousView.isReadOnly = true
        for v in [previousView, gutter, pageView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            pageHost.addSubview(v)
        }

        let top = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? root.topAnchor
        shelfWidth = shelf.view.widthAnchor.constraint(equalToConstant: 0)
        // Space right of the shelf; the page is centered in it, up to 1280pt wide
        let area = NSLayoutGuide()
        root.addLayoutGuide(area)
        // Below the window's size-holding priority (500) so the page never shrinks the window
        let fill = pageHost.widthAnchor.constraint(equalTo: area.widthAnchor)
        fill.priority = NSLayoutConstraint.Priority(490)

        NSLayoutConstraint.activate([
            shelf.view.topAnchor.constraint(equalTo: root.topAnchor),
            shelf.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            shelf.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            shelfWidth,

            area.leadingAnchor.constraint(equalTo: shelf.view.trailingAnchor),
            area.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            pageHost.topAnchor.constraint(equalTo: top, constant: 12),
            pageHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            pageHost.centerXAnchor.constraint(equalTo: area.centerXAnchor),
            pageHost.widthAnchor.constraint(lessThanOrEqualTo: area.widthAnchor),
            fill,

            pageView.topAnchor.constraint(equalTo: pageHost.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
            pageView.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            previousView.topAnchor.constraint(equalTo: pageHost.topAnchor),
            previousView.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
            previousView.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: pageHost.topAnchor, constant: 8),
            gutter.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor, constant: -20),
            gutter.widthAnchor.constraint(equalToConstant: 1),
        ])
        closedView.isHidden = true
        root.addSubview(closedView)
        NSLayoutConstraint.activate([
            closedView.topAnchor.constraint(equalTo: root.topAnchor),
            closedView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            closedView.leadingAnchor.constraint(equalTo: shelf.view.trailingAnchor),
            closedView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        maxPageWidth = pageHost.widthAnchor.constraint(lessThanOrEqualToConstant: 1280)
        maxPageWidth.isActive = true

        singleConstraints = [pageView.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor)]
        spreadConstraints = [
            gutter.centerXAnchor.constraint(equalTo: pageHost.centerXAnchor),
            previousView.trailingAnchor.constraint(equalTo: gutter.leadingAnchor, constant: -12),
            pageView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor, constant: 12),
        ]
    }

    // MARK: - Showing

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        enterFullScreenIfNeeded()
    }

    /// Macnell only runs full screen
    func enterFullScreenIfNeeded() {
        if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        // The green button would leave full screen; there is no windowed mode
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // Anything that still takes the window out of full screen puts it straight back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.enterFullScreenIfNeeded() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of closing; the app keeps running in the background
        NSApp.hide(nil)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        store.flush()
    }

    private func showCurrentPage(direction: Int) {
        if direction != 0, let layer = pageHost.layer {
            let t = CATransition()
            t.type = .push
            t.subtype = direction > 0 ? .fromRight : .fromLeft
            t.duration = 0.28
            t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(t, forKey: "flip")
        }
        let nb = store.notebook
        pageView.setLayout(nb.layout)
        pageView.load(store.page, index: nb.currentPage, count: nb.pages.count)
        if store.data.twoPageView {
            previousView.setLayout(nb.layout)
            if nb.currentPage > 0 {
                previousView.load(nb.pages[nb.currentPage - 1], index: nb.currentPage - 1, count: nb.pages.count)
            } else {
                previousView.loadEmpty(message: "No earlier page")
            }
        }
        pageView.focusPrimary()
    }

    private func bounce(_ direction: Int) {
        guard let layer = pageHost.layer else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let d = CGFloat(-direction)
        a.values = [0, 14 * d, -5 * d, 0]
        a.keyTimes = [0, 0.35, 0.7, 1]
        a.duration = 0.28
        layer.add(a, forKey: "bounce")
    }

    // MARK: - Closing the notebook

    /// ⌘W: cover over the page, like shutting a paper notebook. Pressed again on the cover, it
    /// closes the window (Macnell hides and keeps running).
    @objc func closeNotebook() {
        guard overlay == nil else { return }
        if isClosed {
            NSApp.hide(nil)
            return
        }
        store.flush()
        closedView.show(store.notebook, theme: store.data.theme)
        closedView.alphaValue = 0
        closedView.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            closedView.animator().alphaValue = 1
        }
        window.makeFirstResponder(closedView)
    }

    /// Coming back after the window was closed: open straight to the page unless Settings says cover
    func prepareForReopen() {
        guard isClosed, !store.data.reopenShowsCover else { return }
        closedView.isHidden = true
        pageView.focusPrimary()
    }

    private func openNotebook() {
        guard isClosed else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            closedView.animator().alphaValue = 0
        }, completionHandler: { [self] in
            closedView.isHidden = true
            closedView.alphaValue = 1
        })
        pageView.focusPrimary()
    }

    // MARK: - Two-page view

    /// Previous page on the left (read-only), current page on the right; flipping still moves one page
    func setTwoPageView(_ on: Bool) {
        store.data.twoPageView = on
        applyPageMode()
        showCurrentPage(direction: 0)
    }

    private func applyPageMode() {
        let on = store.data.twoPageView
        NSLayoutConstraint.deactivate(on ? singleConstraints : spreadConstraints)
        NSLayoutConstraint.activate(on ? spreadConstraints : singleConstraints)
        previousView.isHidden = !on
        gutter.isHidden = !on
        maxPageWidth.constant = on ? 2400 : 1280
    }

    // MARK: - Cover shelf

    @objc func toggleShelf() {
        shelfVisible.toggle()
        if shelfVisible {
            shelf.reload()
            shelf.view.isHidden = false
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.allowsImplicitAnimation = true
            shelfWidth.animator().constant = shelfVisible ? CoverShelf.width : 0
            root.layoutSubtreeIfNeeded()
        }, completionHandler: { [self] in
            if !shelfVisible { shelf.view.isHidden = true }
        })
    }

    private func notebooksChanged() {
        if shelfVisible { shelf.reload() }
        if isClosed { closedView.show(store.notebook, theme: store.data.theme) }
    }

    private func selectNotebook(_ n: Int) {
        openNotebook()
        guard n != store.data.currentNotebook else { return }
        store.data.currentNotebook = n
        showCurrentPage(direction: 0)
        notebooksChanged()
    }

    // MARK: - Pages

    func go(_ delta: Int) {
        guard overlay == nil, !isClosed else { return }
        var nb = store.notebook
        let target = nb.currentPage + delta
        if target < 0 { bounce(delta); return }
        if target >= nb.pages.count { nb.pages.append(Page()) }
        let added = nb.pages.count != store.notebook.pages.count
        nb.currentPage = target
        store.notebook = nb
        showCurrentPage(direction: delta)
        if added { notebooksChanged() }
    }

    @objc func previousPage() { go(-1) }
    @objc func nextPage() { go(1) }

    @objc func previousSection() { if !isClosed { pageView.moveSection(by: -1) } }
    @objc func nextSection() { if !isClosed { pageView.moveSection(by: 1) } }

    /// ⌘T: adds a new page at the end and opens it
    @objc func newPage() {
        openNotebook()
        var nb = store.notebook
        nb.pages.append(Page())
        nb.currentPage = nb.pages.count - 1
        store.notebook = nb
        showCurrentPage(direction: 1)
        pageView.focusTitle()
        notebooksChanged()
    }

    @objc func deleteCurrentPage() {
        guard !isClosed else { return }
        let remove = { [self] in
            var nb = store.notebook
            if nb.pages.count == 1 {
                nb.pages = [Page()]
            } else {
                nb.pages.remove(at: nb.currentPage)
                nb.currentPage = min(nb.currentPage, nb.pages.count - 1)
            }
            store.notebook = nb
            showCurrentPage(direction: -1)
            notebooksChanged()
        }
        if store.page.isBlank { remove(); return }
        confirm("Delete this page?", detail: "This can't be undone.", action: "Delete Page", then: remove)
    }

    // MARK: - Notebooks

    @objc func addNotebook() { editCover(nil) }

    /// Cover editor for a new (`nil`) or existing notebook: live cover preview, title, description, color
    private func editCover(_ n: Int?) {
        let theme = store.data.theme
        let count = store.data.notebooks.count
        var draft = n.map { store.data.notebooks[$0] }
            ?? Notebook(name: "Notebook \(count + 1)", cover: CoverColor.allCases[count % CoverColor.allCases.count])

        let preview = CoverView(notebook: draft, isCurrent: false, accent: theme.accent)
        let heading = NSTextField(labelWithString: n == nil ? "New notebook" : "Edit cover")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.textColor = theme.text
        let (titleWell, titleField) = makeThemedField(draft.name, placeholder: "Title", theme: theme)
        let (subtitleWell, subtitleField) = makeThemedField(draft.subtitle, placeholder: "A short description", theme: theme)
        let picker = CoverColorPicker(selected: draft.cover, ringColor: theme.text)
        let layouts = PillPicker(options: PageLayout.allCases.map(\.label),
                                 selected: PageLayout.allCases.firstIndex(of: draft.layout) ?? 0, theme: theme)

        let fieldsDelegate = CoverFieldsDelegate { [weak preview] in
            draft.name = titleField.stringValue
            draft.subtitle = subtitleField.stringValue
            preview?.notebook = draft
        }
        titleField.delegate = fieldsDelegate
        subtitleField.delegate = fieldsDelegate
        picker.onChange = { [weak preview] cover in
            draft.cover = cover
            preview?.notebook = draft
        }

        let save = { [self] in
            withExtendedLifetime(fieldsDelegate) {}
            let name = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = subtitleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let layout = PageLayout.allCases[layouts.selected]
            if let n {
                if !name.isEmpty { store.data.notebooks[n].name = name }
                store.data.notebooks[n].subtitle = subtitle
                store.data.notebooks[n].cover = picker.selected
                store.data.notebooks[n].layout = layout
                if n == store.data.currentNotebook { showCurrentPage(direction: 0) }
            } else {
                store.data.notebooks.append(Notebook(name: name.isEmpty ? "Notebook \(count + 1)" : name,
                                                     subtitle: subtitle, cover: picker.selected, layout: layout))
                store.data.currentNotebook = store.data.notebooks.count - 1
                showCurrentPage(direction: 0)
            }
            dismissOverlay()
            notebooksChanged()
        }
        fieldsDelegate.onReturn = save
        fieldsDelegate.onCancel = { [weak self] in self?.dismissOverlay() }

        let buttons = NSStackView(views: [
            ThemedButton("Cancel", style: .plain, theme: theme) { [weak self] in self?.dismissOverlay() },
            ThemedButton(n == nil ? "Create" : "Save", style: .primary, theme: theme, handler: save),
        ])
        buttons.spacing = 8
        let form = NSStackView(views: [heading, makeCaption("Title", theme: theme), titleWell,
                                       makeCaption("Description", theme: theme), subtitleWell,
                                       makeCaption("Cover", theme: theme), picker,
                                       makeCaption("Page layout", theme: theme), layouts])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 6
        form.setCustomSpacing(18, after: heading)
        form.setCustomSpacing(14, after: titleWell)
        form.setCustomSpacing(14, after: subtitleWell)
        form.setCustomSpacing(14, after: picker)

        let card = CardView(theme: theme)
        for v in [preview, form, buttons, titleWell, subtitleWell] { v.translatesAutoresizingMaskIntoConstraints = false }
        [preview, form, buttons].forEach(card.addSubview)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 560),
            preview.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            preview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            preview.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -20),
            form.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            form.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 24),
            form.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            titleWell.widthAnchor.constraint(equalTo: form.widthAnchor),
            subtitleWell.widthAnchor.constraint(equalTo: form.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: form.trailingAnchor),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: form.bottomAnchor, constant: 20),
            buttons.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
            buttons.bottomAnchor.constraint(greaterThanOrEqualTo: preview.bottomAnchor, constant: -8),
        ])
        presentModal(card, onConfirm: save, focus: titleField)
    }

    private func showCoverMenu(_ n: Int, at windowPoint: NSPoint) {
        presentMenu([
            ("Edit cover", false, { [weak self] in self?.editCover(n) }),
            ("Delete notebook", true, { [weak self] in self?.deleteNotebook(n) }),
        ], at: windowPoint)
    }

    private func deleteNotebook(_ n: Int) {
        let nb = store.data.notebooks[n]
        let count = nb.pages.count == 1 ? "1 page" : "\(nb.pages.count) pages"
        confirm("Delete “\(nb.name)”?", detail: "Its \(count) will be deleted. This can't be undone.", action: "Delete Notebook") { [self] in
            store.data.notebooks.remove(at: n)
            if store.data.currentNotebook >= n { store.data.currentNotebook -= 1 }
            store.sanitize()
            showCurrentPage(direction: 0)
            notebooksChanged()
        }
    }

    // MARK: - Theme & dates

    func setTheme(_ theme: Theme) {
        store.data.theme = theme
        applyTheme()
    }

    func applyTextSize() {
        pageView.applyTextSize()
        previousView.applyTextSize()
    }

    func refreshDates() {
        pageView.refreshDate()
        previousView.refreshDate()
    }

    private func applyTheme() {
        let theme = store.data.theme
        window.appearance = theme.appearance
        window.backgroundColor = theme.background
        root.color = theme.background
        pageHost.color = theme.background
        shelf.apply(theme)
        if isClosed { closedView.show(store.notebook, theme: theme) }
        pageView.apply(theme)
        previousView.apply(theme)
        gutter.color = theme.divider
    }

    // MARK: - Swipe to flip

    private func installSwipeMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window, self.overlay == nil, !self.isClosed else { return event }
            // Let the shelf scroll normally
            if self.shelfVisible, let hit = self.root.hitTest(self.root.convert(event.locationInWindow, from: nil)),
               hit.isDescendant(of: self.shelf.view) { return event }
            return self.handleScroll(event)
        }
    }

    private func handleScroll(_ e: NSEvent) -> NSEvent? {
        let now = ProcessInfo.processInfo.systemUptime
        let phaseless = e.phase.isEmpty && e.momentumPhase.isEmpty
        if e.phase.contains(.began) || (phaseless && now - lastWheelTime > 0.35) {
            swipeAxis = .undecided
            swipeAccum = 0
            swipeFired = false
        }
        lastWheelTime = now

        // Swallow inertia that follows a horizontal gesture
        if !e.momentumPhase.isEmpty { return swipeAxis == .horizontal ? nil : e }

        let scale: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 12
        let dx = e.scrollingDeltaX * scale
        let dy = e.scrollingDeltaY * scale
        if swipeAxis == .undecided {
            guard abs(dx) + abs(dy) > 1.5 else { return e }
            swipeAxis = abs(dx) > abs(dy) * 1.3 ? .horizontal : .vertical
        }
        guard swipeAxis == .horizontal else { return e }

        swipeAccum += dx
        if !swipeFired, abs(swipeAccum) > 70 {
            swipeFired = true
            // With natural scrolling the delta follows the fingers
            let fingersRight = e.isDirectionInvertedFromDevice ? swipeAccum > 0 : swipeAccum < 0
            go(fingersRight ? -1 : 1)
        }
        return nil
    }

    // MARK: - Themed overlays

    private func confirm(_ title: String, detail: String, action: String, then: @escaping () -> Void) {
        let theme = store.data.theme
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.textColor = theme.text
        heading.lineBreakMode = .byTruncatingTail
        let message = NSTextField(wrappingLabelWithString: detail)
        message.font = .systemFont(ofSize: 13)
        message.textColor = theme.secondaryText
        let run = { [weak self] in
            self?.dismissOverlay()
            then()
        }
        let buttons = NSStackView(views: [
            ThemedButton("Cancel", style: .plain, theme: theme) { [weak self] in self?.dismissOverlay() },
            ThemedButton(action, style: .destructive, theme: theme, handler: run),
        ])
        buttons.spacing = 8

        let card = CardView(theme: theme)
        for v in [heading, message, buttons] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 360),
            heading.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            heading.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -24),
            message.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            message.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            buttons.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 22),
            buttons.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])
        presentModal(card, onConfirm: run, focus: nil)
    }

    private func presentModal(_ card: NSView, onConfirm: @escaping () -> Void, focus: NSView?) {
        let layer = OverlayView(dimmed: true, theme: store.data.theme)
        layer.onDismiss = { [weak self] in self?.dismissOverlay() }
        layer.onConfirm = onConfirm
        card.translatesAutoresizingMaskIntoConstraints = false
        layer.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: layer.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: layer.centerYAnchor, constant: -40),
        ])
        install(layer)
        window.makeFirstResponder(focus ?? layer)
    }

    /// Small themed menu that opens where you right-clicked
    private func presentMenu(_ items: [(title: String, destructive: Bool, action: () -> Void)], at windowPoint: NSPoint) {
        let theme = store.data.theme
        let layer = OverlayView(dimmed: false, theme: theme)
        layer.onDismiss = { [weak self] in self?.dismissOverlay() }

        let card = CardView(theme: theme, radius: 10)
        let rows = NSStackView(views: items.map { item in
            MenuRow(item.title, destructive: item.destructive, theme: theme) { [weak self] in
                self?.dismissOverlay()
                item.action()
            }
        })
        rows.orientation = .vertical
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: card.topAnchor, constant: 5),
            rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -5),
            rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 5),
            rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -5),
            rows.widthAnchor.constraint(equalToConstant: 180),
        ])
        rows.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }

        install(layer)
        let size = card.fittingSize
        let p = root.convert(windowPoint, from: nil)
        let x = min(max(8, p.x), root.bounds.width - size.width - 8)
        let y = min(max(8, p.y - size.height), root.bounds.height - size.height - 8)
        card.translatesAutoresizingMaskIntoConstraints = true
        card.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        layer.addSubview(card)
        window.makeFirstResponder(layer)
    }

    private func install(_ layer: OverlayView) {
        overlay?.removeFromSuperview()
        overlay = layer
        root.addSubview(layer)
        NSLayoutConstraint.activate([
            layer.topAnchor.constraint(equalTo: root.topAnchor),
            layer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            layer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            layer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        layer.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            layer.animator().alphaValue = 1
        }
    }

    private func dismissOverlay() {
        guard let layer = overlay else { return }
        overlay = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            layer.animator().alphaValue = 0
        }, completionHandler: { layer.removeFromSuperview() })
        pageView.focusPrimary()
    }
}

/// Live-updates the cover preview and maps Return / Esc in the cover editor's fields
private final class CoverFieldsDelegate: NSObject, NSTextFieldDelegate {
    let onEdit: () -> Void
    var onReturn: (() -> Void)?
    var onCancel: (() -> Void)?

    init(onEdit: @escaping () -> Void) { self.onEdit = onEdit }

    func controlTextDidChange(_ obj: Notification) { onEdit() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): onReturn?(); return true
        case #selector(NSResponder.cancelOperation(_:)): onCancel?(); return true
        default: return false
        }
    }
}
