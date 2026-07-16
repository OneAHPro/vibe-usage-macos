import Testing
@testable import VibeUsage

struct ConfigTests {
    @Test
    func legacyApiKeyDoesNotCountAsNewSystemLogin() {
        let config = VibeUsageConfig(apiKey: "legacy-key", apiUrl: "https://vibecafe.ai", lastSync: nil)

        #expect(config.isRemoteAccountConfigured == false)
    }

    @Test
    func savedUserIdCountsAsNewSystemLogin() {
        let config = VibeUsageConfig(
            apiKey: nil,
            apiUrl: "https://api.anhepro.com",
            lastSync: nil,
            userID: 7,
            username: "xuande"
        )

        #expect(config.isRemoteAccountConfigured)
    }
}
