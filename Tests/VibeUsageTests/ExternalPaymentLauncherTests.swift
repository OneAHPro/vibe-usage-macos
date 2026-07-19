import Foundation
import Testing
@testable import VibeUsage

@MainActor
struct ExternalPaymentLauncherTests {
    @Test
    func formCheckoutEscapesContentWritesPrivateFileAndSchedulesRemoval() throws {
        let recorder = PaymentLaunchRecorder()
        let launcher = ExternalPaymentLauncher(
            openURL: { recorder.openedURL = $0; return true },
            writePrivateFile: { data, url in
                recorder.writtenData = data
                recorder.writtenURL = url
                recorder.permissions = 0o600
            },
            scheduleRemoval: { recorder.removalURL = $0 },
            temporaryDirectory: { URL(fileURLWithPath: "/private/tmp") }
        )

        try launcher.launch(.form(
            action: URL(string: "https://pay.example.com/a?x=1&y=2")!,
            fields: ["na<me": "a&\"b"]
        ))

        let html = try #require(recorder.writtenData.flatMap { String(data: $0, encoding: .utf8) })
        #expect(html.contains("method=\"POST\""))
        #expect(html.contains("https://pay.example.com/a?x=1&amp;y=2"))
        #expect(html.contains("na&lt;me"))
        #expect(html.contains("a&amp;&quot;b"))
        #expect(recorder.permissions == 0o600)
        #expect(recorder.openedURL == recorder.writtenURL)
        #expect(recorder.removalURL == recorder.writtenURL)
    }

    @Test
    func directCheckoutRejectsNonWebURLs() throws {
        let recorder = PaymentLaunchRecorder()
        let launcher = ExternalPaymentLauncher(
            openURL: { recorder.openedURL = $0; return true },
            writePrivateFile: { _, _ in },
            scheduleRemoval: { _ in },
            temporaryDirectory: { URL(fileURLWithPath: "/private/tmp") }
        )

        #expect(throws: ExternalPaymentLauncher.LaunchError.invalidURL) {
            try launcher.launch(.url(URL(string: "file:///etc/passwd")!))
        }
        #expect(recorder.openedURL == nil)
    }

    @Test
    func liveFormLauncherTargetsTheDefaultHTTPSBrowser() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("VibeUsage/Services/ExternalPaymentLauncher.swift"),
            encoding: .utf8
        )

        #expect(source.contains("urlForApplication(toOpen:"))
        #expect(source.contains("withApplicationAt: browserURL"))
    }
}

@MainActor
private final class PaymentLaunchRecorder {
    var openedURL: URL?
    var writtenData: Data?
    var writtenURL: URL?
    var removalURL: URL?
    var permissions: Int?
}
