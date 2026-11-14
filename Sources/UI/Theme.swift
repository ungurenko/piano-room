import SwiftUI

/// Тёплая светлая палитра приложения.
enum Theme {
    /// Интервалы по близости: подпись, группа, содержимое панели, раздел экрана.
    enum Space {
        static let tight: CGFloat = 4
        static let related: CGFloat = 8
        static let control: CGFloat = 12
        static let group: CGFloat = 16
        static let section: CGFloat = 24
        static let spacious: CGFloat = 32
    }

    enum Layout {
        static let instrumentsWidth: CGFloat = 280
        static let effectsWidth: CGFloat = 288
        static let maximumWidth: CGFloat = 1568
    }

    static let backgroundTop = Color(hex: 0xFFFAF2)
    static let background = Color(hex: 0xF5EFE5)
    static let backgroundBottom = Color(hex: 0xEDE2D2)

    static let panel = Color(hex: 0xFFFCF7)
    static let text = Color(hex: 0x372F27)
    static let muted = Color(hex: 0x94887B)
    static let mutedSoft = Color(hex: 0xB3A696)

    static let accent = Color(hex: 0xC07C45)
    static let accentDeep = Color(hex: 0xA4652F)
    static let accentSoft = Color(hex: 0xF3DDBD)
    static let accentPale = Color(hex: 0xFBEEDB)

    static let line = Color(hex: 0x7A5F40).opacity(0.13)
    static let lineStrong = Color(hex: 0x7A5F40).opacity(0.22)
    static let shadow = Color(hex: 0x785837).opacity(0.10)
    static let shadowSoft = Color(hex: 0x785837).opacity(0.07)

    static let pianoBlack = Color(hex: 0x352C24)
    static let pianoBlackSoft = Color(hex: 0x4A3F35)

    static let gradient = LinearGradient(
        colors: [backgroundTop, background, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
