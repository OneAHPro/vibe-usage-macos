import Foundation

@MainActor
protocol NewSystemClient {
    func login(username: String, password: String) async throws -> LoginOutcome
    func verifyTwoFactor(code: String) async throws -> AuthenticatedUser
    func fetchCurrentUser() async throws -> AuthenticatedUser
    func logout() async throws
    func fetchLeaderboard() async throws -> LeaderboardData
    func fetchUsage(range: UsageQueryRange) async throws -> UsageResponse
    func fetchQuotaPerUnit() async -> Double
}

extension APIClient: NewSystemClient {}

@MainActor
struct AppStateDependencies {
    var loadConfig: () -> VibeUsageConfig?
    var saveConfig: (VibeUsageConfig) -> Void
    var clearConfig: () -> Void
    var makeClient: (_ baseURL: String, _ userID: Int?) -> any NewSystemClient
    var now: () -> Date

    static let live = AppStateDependencies(
        loadConfig: ConfigManager.load,
        saveConfig: ConfigManager.save,
        clearConfig: ConfigManager.clear,
        makeClient: { APIClient(baseURL: $0, userID: $1) },
        now: Date.init
    )
}
