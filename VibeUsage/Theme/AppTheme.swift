import AppKit
import SwiftUI

enum AppTheme {
    enum Token {
        case windowBackground
        case surface
        case raisedSurface
        case subtleSurface
        case separator
        case primaryText
        case secondaryText
        case tertiaryText
        case quaternaryText
        case selectionBackground
        case tooltipBackground
    }

    static var windowBackground: Color { color(.windowBackground) }
    static var surface: Color { color(.surface) }
    static var raisedSurface: Color { color(.raisedSurface) }
    static var subtleSurface: Color { color(.subtleSurface) }
    static var separator: Color { color(.separator) }
    static var primaryText: Color { color(.primaryText) }
    static var secondaryText: Color { color(.secondaryText) }
    static var tertiaryText: Color { color(.tertiaryText) }
    static var quaternaryText: Color { color(.quaternaryText) }
    static var selectionBackground: Color { color(.selectionBackground) }
    static var tooltipBackground: Color { color(.tooltipBackground) }
    static let costAccent = Color(red: 0.06, green: 0.73, blue: 0.51)

    static func nsColor(_ token: Token) -> NSColor {
        switch token {
        case .windowBackground:
            return .windowBackgroundColor
        case .surface:
            return .controlBackgroundColor
        case .raisedSurface:
            return .textBackgroundColor
        case .subtleSurface:
            return NSColor(name: "VibeUsageDashboardCanvas") { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return NSColor(srgbRed: 0.067, green: 0.075, blue: 0.086, alpha: 1)
                }
                return NSColor(srgbRed: 0.957, green: 0.961, blue: 0.969, alpha: 1)
            }
        case .separator:
            return .separatorColor
        case .primaryText:
            return .labelColor
        case .secondaryText:
            return .secondaryLabelColor
        case .tertiaryText:
            return .tertiaryLabelColor
        case .quaternaryText:
            return .quaternaryLabelColor
        case .selectionBackground:
            return .unemphasizedSelectedContentBackgroundColor
        case .tooltipBackground:
            return .controlBackgroundColor
        }
    }

    static func resolvedSRGB(_ token: Token, appearance appearanceName: NSAppearance.Name) -> NSColor {
        guard let appearance = NSAppearance(named: appearanceName) else {
            return nsColor(token).usingColorSpace(.sRGB) ?? nsColor(token)
        }

        var result = nsColor(token)
        appearance.performAsCurrentDrawingAppearance {
            let resolved = nsColor(token)
            result = resolved.usingColorSpace(.sRGB) ?? resolved
        }
        return result
    }

    private static func color(_ token: Token) -> Color {
        Color(nsColor: nsColor(token))
    }
}
