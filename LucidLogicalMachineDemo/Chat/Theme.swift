import SwiftUI

/// Design tokens for the chat screen's "technical console" theme.
enum ChatTheme {
    static let bg = Color(red: 0.075, green: 0.078, blue: 0.086)
    static let surface = Color(red: 0.098, green: 0.102, blue: 0.113)
    static let surface2 = Color(red: 0.122, green: 0.127, blue: 0.141)
    static let border = Color(red: 0.176, green: 0.182, blue: 0.2)

    static let text = Color(red: 0.96, green: 0.96, blue: 0.965)
    static let textSecondary = Color(red: 0.66, green: 0.68, blue: 0.7)
    static let textTertiary = Color(red: 0.49, green: 0.51, blue: 0.53)

    static let accent = Color(red: 0.482, green: 0.831, blue: 0.647)
    static let accentStrong = Color(red: 0.35, green: 0.75, blue: 0.56)
    static let accentBg = accent.opacity(0.16)
    static let accentBgStrong = accent.opacity(0.28)
    static let accentOn = Color(red: 0.06, green: 0.1, blue: 0.08)

    static let danger = Color(red: 0.86, green: 0.35, blue: 0.32)

    static func title(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
