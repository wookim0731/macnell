import AppKit

enum Theme: String, Codable, CaseIterable {
    case white, yellow, black

    var label: String {
        switch self {
        case .white: "White"
        case .yellow: "Yellow"
        case .black: "Black"
        }
    }

    var background: NSColor {
        switch self {
        case .white: NSColor(hex: 0xFFFFFF)
        case .yellow: NSColor(hex: 0xFBF3C2)   // legal-pad / Oxford yellow
        case .black: NSColor(hex: 0x1C1C1E)
        }
    }

    /// Background of the ⌘\ cover shelf
    var shelfBackground: NSColor {
        switch self {
        case .white: NSColor(hex: 0xF2F2F4)
        case .yellow: NSColor(hex: 0xF0E6B2)
        case .black: NSColor(hex: 0x141416)
        }
    }

    /// Raised surface for cards and menus
    var surface: NSColor {
        switch self {
        case .white: NSColor(hex: 0xFFFFFF)
        case .yellow: NSColor(hex: 0xFFFBE6)
        case .black: NSColor(hex: 0x2A2A2D)
        }
    }

    static let danger = NSColor(hex: 0xD6453B)

    var text: NSColor {
        switch self {
        case .white: NSColor(hex: 0x1D1D1F)
        case .yellow: NSColor(hex: 0x2B2924)
        case .black: NSColor(hex: 0xECECEC)
        }
    }

    var secondaryText: NSColor {
        switch self {
        case .white: NSColor(hex: 0x8A8A8E)
        case .yellow: NSColor(hex: 0x8C846A)
        case .black: NSColor(hex: 0x8E8E93)
        }
    }

    /// Cornell section rules
    var divider: NSColor {
        switch self {
        case .white: NSColor(hex: 0xE3E3E8)
        case .yellow: NSColor(hex: 0xDFA3A3)   // legal-pad red margin line
        case .black: NSColor(hex: 0x333336)
        }
    }

    var accent: NSColor {
        switch self {
        case .white: NSColor(hex: 0x2F6FEB)
        case .yellow: NSColor(hex: 0x3D6FA8)   // ruled-line blue
        case .black: NSColor(hex: 0x0A84FF)
        }
    }

    var appearance: NSAppearance? {
        NSAppearance(named: self == .black ? .darkAqua : .aqua)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension CoverColor {
    /// Leather tone of a notebook cover
    var color: NSColor {
        switch self {
        case .green: NSColor(hex: 0x3F6B53)
        case .navy: NSColor(hex: 0x2D3F5E)
        case .burgundy: NSColor(hex: 0x6E2F38)
        case .charcoal: NSColor(hex: 0x2E2E31)
        case .tan: NSColor(hex: 0x9A7853)
        case .slate: NSColor(hex: 0x6C7680)
        }
    }
}
