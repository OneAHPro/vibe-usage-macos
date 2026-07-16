import Foundation

enum AppConfig {
    static let version = "0.6.0"

    #if DEBUG
    static let defaultApiUrl = "http://localhost:3000"
    static let accountConfigFileName = "desktop-account.dev.json"
    static let isDev = true
    #else
    static let defaultApiUrl = "https://api.anhepro.com"
    static let accountConfigFileName = "desktop-account.json"
    static let isDev = false
    #endif
}
