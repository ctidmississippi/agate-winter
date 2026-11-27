import SwiftUI
import CoreText

enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
    static let paper = dyn(0xf1efea, 0x161513)
    static let ink = dyn(0x161616, 0xeeebe4)
    static let ink2 = dyn(0x363533, 0xcfccc4)
    static let muted = dyn(0x6e6c67, 0x9a978f)
    static let rule = dyn(0xcfccc4, 0x3a3834)
    static let accent = dyn(0x8b1a1a, 0xe0746b)
    static let shade = dyn(0xe5e2db, 0x24221f)

    /// Fixed light colors, used for the shareable clipping so it looks the same in either mode.
    enum Light {
        static let paper = Color(uiColor: UIColor(hex: 0xf1efea))
        static let ink = Color(uiColor: UIColor(hex: 0x161616))
        static let muted = Color(uiColor: UIColor(hex: 0x6e6c67))
        static let rule = Color(uiColor: UIColor(hex: 0xcfccc4))
        static let accent = Color(uiColor: UIColor(hex: 0x8b1a1a))
    }
}

/// One accent color per sport, used on section rules and block titles.
enum SportAccent {
    static func color(_ key: String) -> Color {
        switch key {
        case "football": return Theme.dyn(0x2e6b34, 0x7fc287)
        case "basketball": return Theme.dyn(0xc2561b, 0xf0955f)
        case "hockey": return Theme.dyn(0x1f5f9e, 0x7fb5e8)
        case "baseball": return Theme.dyn(0xa3262a, 0xe8807f)
        case "soccer": return Theme.dyn(0x1d7a6b, 0x6fd0bf)
        case "volleyball", "field-hockey": return Theme.dyn(0x7a4aa0, 0xc4a0e6)
        case "golf": return Theme.dyn(0x4f7a1f, 0xa8d16e)
        case "tennis": return Theme.dyn(0x9a7b00, 0xe6c84d)
        case "racing": return Theme.dyn(0x555555, 0xbdbdbd)
        case "fighting": return Theme.dyn(0xa0306a, 0xe58bb8)
        default: return Theme.ink
        }
    }
}

extension Color {
    /// ESPN team colors arrive as "8c1d40" with no hash.
    init?(espnHex: String?) {
        guard let s = espnHex, s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(uiColor: UIColor(hex: v))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

// Static font instances bundled in Resources/Fonts (PostScript names set at build time).
extension Font {
    static func nameplate(_ size: CGFloat) -> Font { .custom("Chomsky", size: size) }
    static func head(_ size: CGFloat, black: Bool = false) -> Font {
        .custom(black ? "AgateHead-Black" : "AgateHead-Bold", size: size)
    }
    static func line(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "AgateLine-Bold" : "AgateLine-Regular", size: size)
    }
    static func sans(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "AgateSans-Bold" : "AgateSans-Medium", size: size)
    }
}

private struct TextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

enum FontLoader {
    /// Registers every .ttf/.otf in the app bundle so no Info.plist font list is needed.
    static func registerBundledFonts() {
        guard let root = Bundle.main.resourceURL,
              let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in walker {
            let ext = url.pathExtension.lowercased()
            if ext == "ttf" || ext == "otf" {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

struct Rule: View {
    var height: CGFloat = 1
    var color: Color = Theme.ink
    var body: some View { Rectangle().fill(color).frame(height: height) }
}

/// "Double rule" under the dateline, like a newspaper.
struct DoubleRule: View {
    var body: some View {
        VStack(spacing: 2) { Rule(height: 2.5); Rule(height: 0.5) }
    }
}
