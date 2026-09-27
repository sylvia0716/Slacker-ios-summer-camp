import SwiftUI
import CoreText

/// Reference-specific styling, scoped to the agenda card without changing the shared app theme.
enum SmartAgendaStyle {
    static let yellow = Color(red: 1, green: 0.81, blue: 0)
    static let ink = Color(red: 0.075, green: 0.075, blue: 0.07)
    static let paper = Color(red: 0.974, green: 0.958, blue: 0.909)
    static let secondary = Color(red: 0.34, green: 0.37, blue: 0.42)
    static let rule = Color(red: 0.79, green: 0.79, blue: 0.75)
    static let red = BombTheme.red

    static func text(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Arial-BoldMT" : "ArialMT", fixedSize: size)
    }

    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy)
    }

    private static let registerDigits: Void = {
        guard let url = Bundle.main.url(forResource: "DSEG7Classic-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func digits(_ size: CGFloat) -> Font {
        _ = registerDigits
        return .custom("DSEG7Classic-Regular", fixedSize: size)
    }
}
