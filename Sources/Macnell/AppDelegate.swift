import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var main: MainWindowController!
    private let settings = SettingsWindowController()
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        main = MainWindowController()
        settings.onThemeChange = { [weak self] theme in self?.main.setTheme(theme) }
        settings.onDateStyleChange = { [weak self] in self?.main.refreshDates() }
        settings.onTwoPageViewChange = { [weak self] on in self?.main.setTwoPageView(on) }
        settings.onReopenChange = { Store.shared.data.reopenShowsCover = $0 }
        settings.onTextSizeChange = { [weak self] size in
            Store.shared.data.textSize = size
            self?.main.applyTextSize()
        }
        settings.onMenuBarIconChange = { [weak self] shows in
            Store.shared.data.showsMenuBarIcon = shows
            self?.statusItem.isVisible = shows
        }
        buildMainMenu()
        buildStatusItem()

        main.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showNotes()
        return true
    }

    @objc func showNotes() { main.show() }

    func applicationWillUnhide(_ notification: Notification) {
        main.prepareForReopen()
    }
    @objc func showSettings() { settings.show() }

    // MARK: - Menu bar icon

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Macnell")

        let menu = NSMenu()
        menu.addItem(item("Open Macnell", #selector(showNotes)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Quit Macnell", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        statusItem.menu = menu
        statusItem.isVisible = Store.shared.data.showsMenuBarIcon
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = modifiers
        i.target = target ?? self
        return i
    }

    // MARK: - Main menu (hidden for an accessory app, but drives the shortcuts)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item("Settings…", #selector(showSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Macnell", #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
        appMenu.addItem(item("Quit Macnell", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        addSubmenu(appMenu, to: mainMenu)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(edit, to: mainMenu)

        let page = NSMenu(title: "Page")
        // ⇧⌘[ / ⇧⌘] (typed as { and }): one step up from ⌘[ / ⌘] sections, and ⌘←/→ stay free for line start/end
        page.addItem(item("Previous Page", #selector(MainWindowController.previousPage), key: "{", target: main))
        page.addItem(item("Next Page", #selector(MainWindowController.nextPage), key: "}", target: main))
        page.addItem(item("Previous Section", #selector(MainWindowController.previousSection), key: "[", target: main))
        page.addItem(item("Next Section", #selector(MainWindowController.nextSection), key: "]", target: main))
        page.addItem(item("Close Notebook", #selector(MainWindowController.closeNotebook), key: "w", target: main))
        page.addItem(item("New Page", #selector(MainWindowController.newPage), key: "t", target: main))
        page.addItem(.separator())
        page.addItem(item("New Notebook…", #selector(MainWindowController.addNotebook), key: "n",
                          modifiers: [.command, .shift], target: main))
        addSubmenu(page, to: mainMenu)

        let view = NSMenu(title: "View")
        view.addItem(item("Notebook Covers", #selector(MainWindowController.toggleShelf), key: "\\", target: main))
        view.addItem(item("Toggle Full Screen", #selector(MainWindowController.toggleFullScreen), key: "f",
                          modifiers: [.command, .control], target: main))
        addSubmenu(view, to: mainMenu)

        NSApp.mainMenu = mainMenu
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let holder = NSMenuItem()
        holder.submenu = submenu
        menu.addItem(holder)
    }
}
