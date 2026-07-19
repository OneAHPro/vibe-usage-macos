import Foundation
import Testing
@testable import VibeUsage

@MainActor
struct AccountManagementStoreTests {
    @Test
    func tokenStoreLoadsOnceRefreshesExplicitlyAndSearchesOnlyOnSubmit() async {
        let client = FakeAccountClient()
        let store = TokenManagementStore()

        await store.loadIfNeeded(client: client)
        await store.loadIfNeeded(client: client)
        #expect(client.tokenPageCalls == 1)

        store.searchText = "Codex"
        #expect(client.tokenPageCalls == 1)
        await store.submitSearch(client: client)
        #expect(client.tokenPageCalls == 2)
        #expect(client.lastKeyword == "Codex")

        await store.refresh(client: client)
        #expect(client.tokenPageCalls == 3)
    }

    @Test
    func failedTokenRefreshKeepsExistingRows() async {
        let client = FakeAccountClient()
        let store = TokenManagementStore()
        await store.loadIfNeeded(client: client)
        #expect(store.tokens.count == 1)

        client.shouldFailTokenLoad = true
        await store.refresh(client: client)

        #expect(store.tokens.count == 1)
        #expect(store.errorMessage != nil)
    }

    @Test
    func tokenRevealPassesSecretDirectlyToConsumer() async {
        let client = FakeAccountClient()
        let store = TokenManagementStore()
        var received: String?

        await store.revealTokenKey(id: 9, client: client) { key in
            received = key
        }

        #expect(received == "secret-key")
        #expect(client.revealCalls == 1)
    }

    @Test
    func unauthorizedAccountLoadRequestsCentralSessionCleanup() async {
        let client = FakeAccountClient()
        client.tokenLoadError = APIClient.APIError.unauthorized
        let store = TokenManagementStore()

        await store.loadIfNeeded(client: client)

        #expect(store.requiresAuthentication)
        #expect(store.tokens.isEmpty)
    }

    @Test
    func walletStoreLoadsItsThreeResourcesOnlyOnce() async {
        let client = FakeAccountClient()
        let store = WalletManagementStore()

        await store.loadIfNeeded(client: client)
        await store.loadIfNeeded(client: client)

        #expect(client.userCalls == 1)
        #expect(client.topUpInfoCalls == 1)
        #expect(client.topUpPageCalls == 1)

        await store.estimatePayment(.stripe(amount: 20), client: client)
        #expect(store.estimatedPaymentAmount == 10)
        await store.refresh(client: client)
        #expect(store.estimatedPaymentAmount == nil)
        #expect(client.userCalls == 2)
        #expect(client.topUpInfoCalls == 2)
        #expect(client.topUpPageCalls == 2)
    }
}

@MainActor
private final class FakeAccountClient: AccountManagementClient {
    enum Failure: Error { case requested }

    var tokenPageCalls = 0
    var userCalls = 0
    var topUpInfoCalls = 0
    var topUpPageCalls = 0
    var revealCalls = 0
    var lastKeyword: String?
    var shouldFailTokenLoad = false
    var tokenLoadError: Error?

    func fetchCurrentUser() async throws -> AuthenticatedUser {
        userCalls += 1
        return AuthenticatedUser(
            id: 7,
            username: "xuande",
            displayName: "徐安",
            role: 1,
            status: 1,
            group: "pro",
            quota: 5_000_000,
            usedQuota: 2_000_000,
            requestCount: 42
        )
    }

    func fetchTokens(
        page: Int,
        pageSize: Int,
        keyword: String?,
        tokenQuery: String?
    ) async throws -> TokenPage {
        tokenPageCalls += 1
        lastKeyword = keyword
        if let tokenLoadError { throw tokenLoadError }
        if shouldFailTokenLoad { throw Failure.requested }
        return TokenPage(page: page, pageSize: pageSize, total: 1, items: [Self.token])
    }

    func createToken(_ mutation: TokenMutation) async throws {}
    func updateToken(_ mutation: TokenMutation) async throws {}
    func setTokenEnabled(id: Int, enabled: Bool) async throws {}
    func deleteToken(id: Int) async throws {}

    func revealTokenKey(id: Int) async throws -> String {
        revealCalls += 1
        return "secret-key"
    }

    func fetchTopUpInfo() async throws -> TopUpInfo {
        topUpInfoCalls += 1
        return try JSONDecoder().decode(
            TopUpInfo.self,
            from: Data(#"{"enable_online_topup":false,"amount_options":[]}"#.utf8)
        )
    }

    func fetchTopUps(page: Int, pageSize: Int) async throws -> TopUpPage {
        topUpPageCalls += 1
        return TopUpPage(page: page, pageSize: pageSize, total: 0, items: [])
    }

    func fetchPaymentAmount(_ request: PaymentRequest) async throws -> Double { 10 }

    func createPaymentCheckout(_ request: PaymentRequest) async throws -> PaymentCheckout {
        .url(URL(string: "https://pay.example.com")!)
    }

    private static let token = TokenRecord(
        id: 9,
        userID: 7,
        maskedKey: "abcd**********wxyz",
        status: 1,
        name: "Codex",
        createdTime: 0,
        accessedTime: 0,
        expiredTime: -1,
        remainQuota: 1_000_000,
        unlimitedQuota: false,
        modelLimitsEnabled: false,
        modelLimits: "",
        allowIPs: nil,
        usedQuota: 0,
        group: "pro",
        crossGroupRetry: false
    )
}
