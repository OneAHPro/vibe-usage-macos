import AppKit
import Testing
@testable import VibeUsage

struct AppThemeTests {
    @Test
    func backgroundsFollowTheRequestedSystemAppearance() {
        let light = AppTheme.resolvedSRGB(.windowBackground, appearance: .aqua)
        let dark = AppTheme.resolvedSRGB(.windowBackground, appearance: .darkAqua)

        #expect(relativeLuminance(light) > relativeLuminance(dark))
    }

    @Test
    func dashboardCanvasUsesSoftAdaptiveBackgrounds() {
        let light = AppTheme.resolvedSRGB(.subtleSurface, appearance: .aqua)
        let dark = AppTheme.resolvedSRGB(.subtleSurface, appearance: .darkAqua)

        #expect(relativeLuminance(light) > 0.85)
        #expect(relativeLuminance(dark) < 0.04)
    }

    @Test
    func primaryTextKeepsReadableContrastInBothAppearances() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let background = AppTheme.resolvedSRGB(.windowBackground, appearance: appearance)
            let text = AppTheme.resolvedSRGB(.primaryText, appearance: appearance)

            #expect(contrastRatio(background, text) >= 4.5)
        }
    }

    private func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * linearized(Double(rgb.redComponent))
            + 0.7152 * linearized(Double(rgb.greenComponent))
            + 0.0722 * linearized(Double(rgb.blueComponent))
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
