import AppKit
import Foundation
import Testing
@testable import VibeUsage

@MainActor
struct PaymentQRCodeTests {
    @Test
    func signedFormCheckoutBecomesScannableHTTPSURL() throws {
        let checkout = PaymentCheckout.form(
            action: URL(string: "https://pay.example.com/submit?source=desktop")!,
            fields: [
                "pid": "1000",
                "out_trade_no": "USR7NO123",
                "name": "SUB:Pro+",
                "sign": "abc+123&456",
            ]
        )

        let url = try #require(checkout.qrCodeURL)
        #expect(url.absoluteString.contains("name=SUB%3APro%2B"))
        #expect(url.absoluteString.contains("sign=abc%2B123%26456"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })

        #expect(url.scheme == "https")
        #expect(values["source"] == "desktop")
        #expect(values["pid"] == "1000")
        #expect(values["out_trade_no"] == "USR7NO123")
        #expect(values["name"] == "SUB:Pro+")
        #expect(values["sign"] == "abc+123&456")
    }

    @Test
    func qrRendererRejectsUnsafeTargetsAndRendersWebCheckout() throws {
        #expect(PaymentCheckout.url(URL(fileURLWithPath: "/tmp/pay")).qrCodeURL == nil)

        let checkout = PaymentCheckout.url(URL(string: "https://checkout.example.com/pay/123")!)
        let url = try #require(checkout.qrCodeURL)
        let data = try #require(PaymentQRCodeRenderer.pngData(for: url.absoluteString))
        let image = try #require(NSImage(data: data))

        #expect(image.size.width >= 200)
        #expect(image.size.height >= 200)
    }
}
