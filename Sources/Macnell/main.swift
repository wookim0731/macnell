import AppKit

// macOS 26 auto-adds symbols to standard menu items (e.g. Quit); keep menus text-only.
UserDefaults.standard.register(defaults: ["NSMenuEnableActionImages": false])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
