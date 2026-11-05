import Foundation

struct Page: Codable, Identifiable {
    var id = UUID()
    var created = Date()
    var modified = Date()
    var title = ""
    var cue = ""
    var notes = ""
    var summary = ""

    var isBlank: Bool {
        [title, cue, notes, summary].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum CoverColor: String, Codable, CaseIterable {
    case green, navy, burgundy, charcoal, tan, slate
}

/// How a page is divided. Every layout maps onto the same three stored fields
/// (`cue` / `notes` / `summary`), so switching layouts never loses text.
enum PageLayout: String, Codable, CaseIterable {
    case macnell, cornell, blank

    var label: String {
        switch self {
        case .macnell: "Macnell"
        case .cornell: "Cornell"
        case .blank: "Blank"
        }
    }
}

struct Notebook: Codable, Identifiable {
    var id = UUID()
    var name: String
    var subtitle = ""
    var cover: CoverColor = .green
    var layout: PageLayout = .macnell
    var pages: [Page] = [Page()]
    var currentPage = 0
}

extension Notebook {
    // Tolerate files saved before covers existed
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Notebook"
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        cover = try c.decodeIfPresent(CoverColor.self, forKey: .cover) ?? .green
        layout = try c.decodeIfPresent(PageLayout.self, forKey: .layout) ?? .macnell
        pages = try c.decodeIfPresent([Page].self, forKey: .pages) ?? [Page()]
        currentPage = try c.decodeIfPresent(Int.self, forKey: .currentPage) ?? 0
    }
}

enum DateStyle: String, Codable, CaseIterable {
    case slash, dash, medium, long

    private var format: String {
        switch self {
        case .slash: "yyyy/MM/dd"
        case .dash: "yyyy-MM-dd"
        case .medium: "MMM d, yyyy"
        case .long: "EEEE, MMMM d, yyyy"
        }
    }

    private static var formatters: [DateStyle: DateFormatter] = [:]

    func string(from date: Date) -> String {
        if let f = Self.formatters[self] { return f.string(from: date) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = format
        Self.formatters[self] = f
        return f.string(from: date)
    }
}

enum TextSize: String, Codable, CaseIterable {
    case small, medium, large, extraLarge

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra large"
        }
    }

    /// Body text size in points; headings, title and markers scale from it
    var points: CGFloat {
        switch self {
        case .small: 13
        case .medium: 15
        case .large: 17
        case .extraLarge: 20
        }
    }
}

struct LibraryData: Codable {
    var notebooks: [Notebook] = [Notebook(name: "My Notes")]
    var currentNotebook = 0
    var theme: Theme = .yellow
    var dateStyle: DateStyle = .slash
    var twoPageView = false
    /// After the window was closed (⌘W twice): come back to the cover instead of the page
    var reopenShowsCover = false
    var showsMenuBarIcon = true
    var textSize: TextSize = .medium
}

extension LibraryData {
    // Tolerate files saved by older versions that lack newer keys
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notebooks = try c.decodeIfPresent([Notebook].self, forKey: .notebooks) ?? [Notebook(name: "My Notes")]
        currentNotebook = try c.decodeIfPresent(Int.self, forKey: .currentNotebook) ?? 0
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? .yellow
        dateStyle = try c.decodeIfPresent(DateStyle.self, forKey: .dateStyle) ?? .slash
        twoPageView = try c.decodeIfPresent(Bool.self, forKey: .twoPageView) ?? false
        reopenShowsCover = try c.decodeIfPresent(Bool.self, forKey: .reopenShowsCover) ?? false
        showsMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showsMenuBarIcon) ?? true
        textSize = try c.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
    }
}

/// Persists to ~/Library/Application Support/Macnell/library.json
final class Store {
    static let shared = Store()

    var data: LibraryData { didSet { scheduleSave() } }

    private let url: URL
    private var pendingSave: DispatchWorkItem?

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Macnell", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("library.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let raw = try? Data(contentsOf: url) {
            if let decoded = try? decoder.decode(LibraryData.self, from: raw) {
                data = decoded
            } else {
                // Don't overwrite an unreadable file; move it aside as a backup
                let backup = dir.appendingPathComponent("library.broken-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: url, to: backup)
                data = LibraryData()
            }
        } else {
            data = LibraryData()
        }
        sanitize()
    }

    var notebook: Notebook {
        get { data.notebooks[data.currentNotebook] }
        set { data.notebooks[data.currentNotebook] = newValue }
    }

    var page: Page {
        get { notebook.pages[notebook.currentPage] }
        set { notebook.pages[notebook.currentPage] = newValue }
    }

    func sanitize() {
        if data.notebooks.isEmpty { data.notebooks = [Notebook(name: "My Notes")] }
        for i in data.notebooks.indices {
            if data.notebooks[i].pages.isEmpty { data.notebooks[i].pages = [Page()] }
            data.notebooks[i].currentPage = min(max(0, data.notebooks[i].currentPage), data.notebooks[i].pages.count - 1)
        }
        data.currentNotebook = min(max(0, data.currentNotebook), data.notebooks.count - 1)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? encoder.encode(data) else { return }
        try? raw.write(to: url, options: .atomic)
    }
}
