import SwiftUI
import UIKit

/// Accent palettes the user can pick in Settings. Each has a light and a dark variant
/// so the colour keeps its contrast in both appearances.
enum ThemeAccent: String, CaseIterable, Identifiable, Codable {
    case indigo
    case ocean
    case teal
    case mint
    case amber
    case coral
    case rose
    case graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .indigo: return "Indigo"
        case .ocean: return "Ocean"
        case .teal: return "Teal"
        case .mint: return "Mint"
        case .amber: return "Amber"
        case .coral: return "Coral"
        case .rose: return "Rose"
        case .graphite: return "Graphite"
        }
    }

    /// Main accent, adapted to light/dark mode.
    var color: Color {
        switch self {
        case .indigo: return Color(light: 0x585CF4, dark: 0x7E82FF)
        case .ocean: return Color(light: 0x0A7AFF, dark: 0x4DA3FF)
        case .teal: return Color(light: 0x0B8F8A, dark: 0x3DC9C2)
        case .mint: return Color(light: 0x1E9E62, dark: 0x4FD38F)
        case .amber: return Color(light: 0xD98A00, dark: 0xFFB340)
        case .coral: return Color(light: 0xE0603C, dark: 0xFF8A65)
        case .rose: return Color(light: 0xD6336C, dark: 0xFF6B9D)
        case .graphite: return Color(light: 0x3A3A3C, dark: 0xC7C7CC)
        }
    }

    /// Second stop for gradients: a lighter, slightly shifted sibling of the accent.
    var gradientEnd: Color {
        switch self {
        case .indigo: return Color(light: 0x7C6CFF, dark: 0x9C8CFF)
        case .ocean: return Color(light: 0x45B3FF, dark: 0x7CC6FF)
        case .teal: return Color(light: 0x34B7A8, dark: 0x6EDCCF)
        case .mint: return Color(light: 0x4FC98A, dark: 0x8BE7B6)
        case .amber: return Color(light: 0xF2B544, dark: 0xFFD07A)
        case .coral: return Color(light: 0xF2906C, dark: 0xFFB094)
        case .rose: return Color(light: 0xF06292, dark: 0xFF9BC0)
        case .graphite: return Color(light: 0x636366, dark: 0xE5E5EA)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Light, dark or follow the system.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Color {
    /// A colour with separate light and dark values, built from hex RGB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }

    /// The accent the user chose in Settings. Reading it inside a view body keeps the view
    /// in sync with the setting thanks to Observation tracking.
    static var appAccent: Color { AppSettings.shared.accent.color }

    /// Soft tint of the accent for chips and selected backgrounds.
    static var appAccentSoft: Color { AppSettings.shared.accent.color.opacity(0.14) }
}

extension ShapeStyle where Self == Color {
    /// Lets views write `.foregroundStyle(.appAccent)`.
    static var appAccent: Color { Color.appAccent }
}

extension LinearGradient {
    /// Hero gradient built from the chosen accent.
    static var appAccent: LinearGradient { AppSettings.shared.accent.gradient }
}
