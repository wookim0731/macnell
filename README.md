# Macnell

A notes app for macOS that stays running in the background.

## Install

1. Download `Macnell-x.y.z.zip` from [Releases](https://github.com/wookim0731/macnell/releases/latest) and unzip it.
2. Move `Macnell.app` to the Applications folder.
3. Open it. The app isn't signed with an Apple Developer ID yet, so the first time macOS says it can't verify the developer.
   Click **Done**, then go to System Settings → Privacy & Security, scroll down, and click **Open Anyway** next to Macnell.
   (Or run `xattr -dr com.apple.quarantine /Applications/Macnell.app` in Terminal.)

Requires macOS 13 or later, on Apple Silicon or Intel.

## Page layouts

Each notebook has its own page layout. Pick it when you create the notebook, or double-click its cover later to change it.

- **Macnell** (default): To Do / Done / Summary. Double-click a section title on the page to rename it for that notebook.
- **Cornell**: Cues | Notes, with a Summary underneath
- **Blank**: a single notes area

All three layouts store text in the same three fields, so switching layouts never loses anything. Text in sections a layout doesn't show is kept, just hidden.

## Build / run

```bash
./scripts/build-app.sh           # builds build/Macnell.app
./scripts/build-app.sh install   # installs to /Applications and launches
```

You only need the Command Line Tools (Swift 5.10+) to build it, not Xcode. It uses only AppKit and has no external dependencies.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open Macnell | Menu bar icon → Open Macnell (can be hidden in Settings → General), Launchpad, or swipe to its space |
| Close the notebook (shows its cover) | `⌘W`. Press it again to close the window. Click the cover or press Return to open it again. |
| Previous / next page | `⇧⌘[` / `⇧⌘]`, a two-finger horizontal swipe, or the arrows beside the page |
| Move between the title and sections | `⌘[` / `⌘]` |
| Switch between one and two pages (previous page on the left, read-only) | Settings → Pages → Page view |
| New page | `⌘T` (adds a page at the end), or flip past the last page |
| Delete page | Right-click the page → Delete page |
| Notebook covers shelf | `⌘\`: click a cover to open it, double-click to edit its title, description and color |
| Leave full screen for a while | `⌃⌘F` or the green window button. Reopening Macnell goes back to full screen. |
| New notebook | `⇧⌘N`, or "+ New Notebook" at the end of the shelf. Right-click a cover to edit or delete it. |
| Settings (paper color, date format, launch at login) | `⌘,` |

Macnell always runs full screen in its own space. To keep it at the far right, drag it there once in Mission Control, and turn off "Automatically rearrange Spaces based on most recent use" in System Settings → Desktop & Dock.

## Markdown

Supported syntax:

- headings: `#`, `##`, `###`
- checkboxes: `[]`, `[ ]`, `[x]`, `- [ ]` (click one to toggle it)
- lists: `- `
- quotes: `> `

Press Return on a list line to continue the list. Press Return on an empty item to end it.

Your notes are saved to `~/Library/Application Support/Macnell/library.json`.
