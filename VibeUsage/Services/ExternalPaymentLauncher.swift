import AppKit
import Foundation

@MainActor
struct ExternalPaymentLauncher {
    enum LaunchError: LocalizedError, Equatable {
        case invalidURL
        case writeFailed
        case openFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: "支付地址无效"
            case .writeFailed: "无法创建安全支付跳转页"
            case .openFailed: "无法打开默认浏览器"
            }
        }
    }

    var openURL: @MainActor (URL) -> Bool
    var writePrivateFile: (Data, URL) throws -> Void
    var scheduleRemoval: (URL) -> Void
    var temporaryDirectory: () -> URL

    init(
        openURL: @escaping @MainActor (URL) -> Bool = Self.openInDefaultBrowser,
        writePrivateFile: @escaping (Data, URL) throws -> Void = { data, url in
            let created = FileManager.default.createFile(
                atPath: url.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
            guard created else { throw LaunchError.writeFailed }
        },
        scheduleRemoval: @escaping (URL) -> Void = { url in
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: url)
            }
        },
        temporaryDirectory: @escaping () -> URL = { FileManager.default.temporaryDirectory }
    ) {
        self.openURL = openURL
        self.writePrivateFile = writePrivateFile
        self.scheduleRemoval = scheduleRemoval
        self.temporaryDirectory = temporaryDirectory
    }

    func launch(_ checkout: PaymentCheckout) throws {
        switch checkout {
        case .url(let url):
            guard Self.isWebURL(url) else { throw LaunchError.invalidURL }
            guard openURL(url) else { throw LaunchError.openFailed }
        case .form(let action, let fields):
            guard Self.isWebURL(action) else { throw LaunchError.invalidURL }
            let fileURL = temporaryDirectory()
                .appendingPathComponent("vibe-usage-payment-\(UUID().uuidString)")
                .appendingPathExtension("html")
            let html = Self.formHTML(action: action, fields: fields)
            guard let data = html.data(using: .utf8) else { throw LaunchError.writeFailed }
            try writePrivateFile(data, fileURL)
            guard openURL(fileURL) else {
                scheduleRemoval(fileURL)
                throw LaunchError.openFailed
            }
            scheduleRemoval(fileURL)
        }
    }

    static func formHTML(action: URL, fields: [String: String]) -> String {
        let inputs = fields.keys.sorted().map { key in
            let value = fields[key] ?? ""
            return "<input type=\"hidden\" name=\"\(escapeHTML(key))\" value=\"\(escapeHTML(value))\">"
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>正在前往支付</title></head>
        <body>
        <form id="payment" method="POST" action="\(escapeHTML(action.absoluteString))">
        \(inputs)
        <noscript><button type="submit">继续支付</button></noscript>
        </form>
        <script>document.getElementById("payment").submit();</script>
        </body></html>
        """
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "https" || scheme == "http"
    }

    private static func openInDefaultBrowser(_ url: URL) -> Bool {
        guard url.isFileURL else { return NSWorkspace.shared.open(url) }
        guard let webProbe = URL(string: "https://example.com"),
              let browserURL = NSWorkspace.shared.urlForApplication(toOpen: webProbe)
        else { return false }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: browserURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
        return true
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
