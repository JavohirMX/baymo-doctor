import AppKit
import SwiftUI

enum ClinicPalette {
    /// Filled buttons and solid marks. The Figma teal in both appearances.
    static let accent = Color(red: 0.12, green: 0.45, blue: 0.42)

    /// Icons, links, and translucent teal washes. The same teal on a light canvas, and a lighter teal of that hue on a dark canvas.
    static let accentInk = adaptive(light: (0.12, 0.45, 0.42), dark: (0.45, 0.78, 0.74))

    static let sidebar = adaptive(light: (0.965, 0.969, 0.976), dark: (0.11, 0.12, 0.13))
    static let canvas = adaptive(light: (1, 1, 1), dark: (0.14, 0.15, 0.16))
    static let selection = adaptive(light: (0.89, 0.945, 0.935), dark: (0.18, 0.26, 0.25))
    static let separator = adaptive(light: (0.90, 0.91, 0.925), dark: (0.28, 0.30, 0.32))
    static let field = adaptive(light: (0.955, 0.958, 0.965), dark: (0.22, 0.23, 0.25))
    static let primaryText = adaptive(light: (0.11, 0.12, 0.14), dark: (0.96, 0.97, 0.98))
    static let secondaryText = adaptive(light: (0.42, 0.45, 0.49), dark: (0.64, 0.67, 0.71))

    static func foreground(_ tone: ClinicTone) -> Color {
        switch tone {
        case .teal:
            accentInk
        case .amber:
            adaptive(light: (0.55, 0.36, 0.02), dark: (0.95, 0.74, 0.42))
        case .red:
            adaptive(light: (0.68, 0.16, 0.14), dark: (0.96, 0.58, 0.54))
        case .green:
            adaptive(light: (0.10, 0.42, 0.28), dark: (0.55, 0.80, 0.64))
        case .neutral:
            secondaryText
        }
    }

    static func background(_ tone: ClinicTone) -> Color {
        switch tone {
        case .neutral:
            primaryText.opacity(0.08)
        default:
            foreground(tone).opacity(0.16)
        }
    }

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let darkMode = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = darkMode ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }))
    }
}

/// Light, Dark, or Match System. Stored in UserDefaults, outside the clinic SwiftData store.
enum ClinicAppearance: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    static let storageKey = "clinicAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Match System"
        }
    }

    /// `nil` follows the Mac.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }

    static func stored(in defaults: UserDefaults) -> ClinicAppearance {
        guard let raw = defaults.string(forKey: storageKey),
              let value = ClinicAppearance(rawValue: raw) else {
            return .system
        }
        return value
    }

    static var current: ClinicAppearance {
        stored(in: .standard)
    }
}
