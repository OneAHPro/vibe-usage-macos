import Foundation

/// Desktop-only account metadata. Passwords and session cookies are never
/// written here; URLSession owns the HttpOnly cookie from the new system.
struct VibeUsageConfig: Codable {
    var apiKey: String?
    var apiUrl: String?
    var lastSync: String?
    var userID: Int?
    var username: String?

    var isRemoteAccountConfigured: Bool {
        guard let userID else { return false }
        return userID > 0
    }
}

enum ConfigManager {
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vibe-usage")
    // Deliberately separate from the legacy CLI's config.json. Logging in or
    // out of the desktop app must not overwrite a user's existing CLI config.
    private static let configFile = configDir.appendingPathComponent(AppConfig.accountConfigFileName)

    static func load() -> VibeUsageConfig? {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: configFile)
            return try JSONDecoder().decode(VibeUsageConfig.self, from: data)
        } catch {
            print("Failed to load config: \(error)")
            return nil
        }
    }

    /// Save config to disk
    static func save(_ config: VibeUsageConfig) {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configFile)
        } catch {
            print("Failed to save config: \(error)")
        }
    }

    /// Check if config exists and has an API key
    static var isConfigured: Bool {
        load()?.isRemoteAccountConfigured == true
    }

    static func clear() {
        try? FileManager.default.removeItem(at: configFile)
    }
}
