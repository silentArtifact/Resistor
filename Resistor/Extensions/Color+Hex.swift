import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let length = hexSanitized.count

        switch length {
        case 6: // RGB (24-bit)
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        case 8: // ARGB (32-bit)
            self.init(
                red: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                green: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x000000FF) / 255.0,
                opacity: Double((rgb & 0xFF000000) >> 24) / 255.0
            )
        default:
            return nil
        }
    }

    /// A colour that resolves to a different hex in light and dark mode.
    ///
    /// Every other colour in the app is a single fixed hex, which works because
    /// the palette is mid-tone by design. The outcome colours can't be: they are
    /// set as *text* on a tint of themselves, so they have to clear a contrast
    /// floor against a near-white and a near-black background, and no one muted
    /// tone does both. watchOS has no light mode and no dynamic-provider API, so
    /// it takes the dark value directly.
    init(light: String, dark: String) {
        #if os(watchOS)
        self = Color(hex: dark) ?? .gray
        #else
        self = Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light) ?? .gray)
        })
        #endif
    }
}
