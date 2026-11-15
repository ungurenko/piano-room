import AppKit
import SwiftUI

/// «Белый лист» — спокойная светлая тема Piano Room:
/// белый холст, чернильная типографика, один акцент (красный фетр).
enum Theme {
    // MARK: - Интервалы

    enum Space {
        static let tight: CGFloat = 4
        static let related: CGFloat = 8
        static let control: CGFloat = 12
        static let group: CGFloat = 16
        static let section: CGFloat = 24
        static let spacious: CGFloat = 32
    }

    // MARK: - Раскладка

    enum Layout {
        static let instrumentsWidth: CGFloat = 264
        static let effectsWidth: CGFloat = 300
        static let columnGap: CGFloat = 36
        static let horizontalInset: CGFloat = 26
        static let headerHeight: CGFloat = 64
        static let bodyTop: CGFloat = 22
        static let bodyBottom: CGFloat = 16
        static let keyboardGap: CGFloat = 22
        static let keyboardMinHeight: CGFloat = 186
        static let keyboardMaxHeight: CGFloat = 226
        static let keyboardRatio: CGFloat = 0.29
    }

    // MARK: - Палитра

    static let background = Color.white
    static let text = Color(hex: 0x151517)
    static let textSoft = Color(hex: 0x3B3B41)
    static let muted = Color(hex: 0x74747E)
    static let mutedSoft = Color(hex: 0xA2A2AC)

    static let line = Color(hex: 0xEDEDF1)
    static let lineSoft = Color(hex: 0xF4F4F7)
    static let hover = Color(hex: 0xF6F6F8)

    /// Красный фетр — единственный цветовой акцент интерфейса.
    static let accent = Color(hex: 0xE33B25)
    static let accentDeep = Color(hex: 0xC22C1A)
    static let accentWash = Color(hex: 0xFEF0EC)

    static let success = Color(hex: 0x2FA45E)

    static let keyBlackTop = Color(hex: 0x26262B)
    static let keyBlackBottom = Color(hex: 0x111114)
    static let keyBorder = Color(hex: 0xE6E6EC)
    static let keyWhiteTop = Color(hex: 0xFFFFFF)
    static let keyWhiteBottom = Color(hex: 0xF8F8FA)
    static let keyPressed = Color(hex: 0xFFF0EC)

    // MARK: - Типографика

    enum DisplayWeight {
        case regular
        case bold
    }

    enum UIWeight {
        case light
        case regular
        case medium
        case semibold
        case bold
    }

    /// Gran — дисплейный шрифт: имя инструмента, логотип, крупные цифры.
    /// Если шрифт не зарегистрирован (превью, тесты), спокойно берём системный.
    @MainActor
    static func display(_ size: CGFloat, weight: DisplayWeight = .bold) -> Font {
        let name = weight == .bold ? "Gran-Bold" : "Gran-Regular"
        if NSFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: weight == .bold ? .bold : .regular)
    }

    /// Onest — интерфейсный шрифт: подписи, списки, подсказки, клавиатура.
    @MainActor
    static func ui(_ size: CGFloat, weight: UIWeight = .regular) -> Font {
        let name: String
        let systemWeight: Font.Weight
        switch weight {
        case .light:
            name = "Onest-Light"
            systemWeight = .light
        case .regular:
            name = "Onest-Regular"
            systemWeight = .regular
        case .medium:
            name = "Onest-Medium"
            systemWeight = .medium
        case .semibold:
            name = "Onest-SemiBold"
            systemWeight = .semibold
        case .bold:
            name = "Onest-Bold"
            systemWeight = .bold
        }
        if NSFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: systemWeight)
    }
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
