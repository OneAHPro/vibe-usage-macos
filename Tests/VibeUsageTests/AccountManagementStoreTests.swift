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
    func walletStoreLoadsSubscriptionOverviewOnceAndFundingRecordsLazily() async {
        let client = FakeAccountClient()
        let store = WalletManagementStore()

        await store.loadIfNeeded(client: client)
        await store.loadIfNeeded(client: client)

        #expect(client.userCalls == 1)
        #expect(client.topUpInfoCalls == 1)
        #expect(client.subscriptionPlanCalls == 1)
        #expect(client.subscriptionSelfCalls == 1)
        #expect(client.topUpPageCalls == 0)
        #expect(store.plans.first?.title == "Pro")
        #expect(store.billingPreference == .subscriptionFirst)

        await store.estimatePayment(.stripe(amount: 20), client: client)
        #expect(store.estimatedPaymentAmount == 10)
        await store.refresh(client: client, target: .recharge)
        #expect(store.estimatedPaymentAmount == nil)
        #expect(client.userCalls == 2)
        #expect(client.topUpInfoCalls == 2)
        #expect(client.subscriptionPlanCalls == 1)
        #expect(client.subscriptionSelfCalls == 1)
        #expect(client.topUpPageCalls == 0)

        await store.loadFundingRecordsIfNeeded(client: client)
        await store.loadFundingRecordsIfNeeded(client: client)
        #expect(client.topUpPageCalls == 1)

        await store.refreshOverview(client: client)
        #expect(client.userCalls == 3)
        #expect(client.topUpInfoCalls == 3)
        #expect(client.subscriptionPlanCalls == 2)
        #expect(client.subscriptionSelfCalls == 2)
        #expect(client.topUpPageCalls == 1)

        await store.refresh(client: client, target: .records)
        #expect(client.userCalls == 4)
        #expect(client.topUpInfoCalls == 3)
        #expect(client.subscriptionPlanCalls == 2)
        #expect(client.subscriptionSelfCalls == 2)
        #expect(client.topUpPageCalls == 2)
    }

    @Test
    func fundingRecordsCanLoadWhileSubscriptionOverviewIsStillLoading() async {
        let client = FakeAccountClient()
        client.userDelay = .milliseconds(80)
        let store = WalletManagementStore()

        let overview = Task { await store.loadIfNeeded(client: client) }
        while client.userCalls == 0 { await Task.yield() }
        let records = Task { await store.loadFundingRecordsIfNeeded(client: client) }
        await records.value
        await overview.value

        #expect(client.topUpPageCalls == 1)
        #expect(store.hasLoadedFundingRecords)
    }

    @Test
    func resetRejectsAnOlderInFlightWalletOverview() async {
        let client = FakeAccountClient()
        client.userDelay = .milliseconds(80)
        let store = WalletManagementStore()

        let load = Task { await store.loadIfNeeded(client: client) }
        while client.userCalls == 0 { await Task.yield() }
        store.reset()
        await load.value

        #expect(store.user == nil)
        #expect(store.plans.isEmpty)
        #expect(!store.hasLoaded)
    }

    @Test
    func resetPreventsTheSecondStageOfARecordsRefreshFromStarting() async {
        let client = FakeAccountClient()
        client.userDelay = .milliseconds(80)
        let store = WalletManagementStore()

        let refresh = Task { await store.refresh(client: client, target: .records) }
        while client.userCalls == 0 { await Task.yield() }
        store.reset()
        await refresh.value

        #expect(client.topUpPageCalls == 0)
        #expect(!store.hasLoadedFundingRecords)
    }

    @Test
    func successfulRecordsLoadDoesNotClearAConcurrentAuthenticationFailure() async {
        let client = FakeAccountClient()
        client.userError = APIClient.APIError.unauthorized
        client.topUpPageDelay = .milliseconds(60)
        let store = WalletManagementStore()

        async let overview: Void = store.loadIfNeeded(client: client)
        async let records: Void = store.loadFundingRecordsIfNeeded(client: client)
        _ = await (overview, records)

        #expect(store.requiresAuthentication)
        #expect(store.errorMessage != nil)
        #expect(store.hasLoadedFundingRecords)
    }

    @Test
    func rechargeRefreshDoesNotClearAnUnretriedSubscriptionFailure() async {
        let client = FakeAccountClient()
        client.subscriptionPlanError = FakeAccountClient.Failure.requested
        let store = WalletManagementStore()

        await store.loadIfNeeded(client: client)
        #expect(store.errorMessage != nil)
        #expect(!store.hasLoaded)

        await store.refresh(client: client, target: .recharge)
        #expect(store.errorMessage != nil)
        #expect(!store.hasLoaded)

        client.subscriptionPlanError = nil
        await store.refresh(client: client, target: .subscriptions)
        #expect(store.errorMessage == nil)
        #expect(store.hasLoaded)
    }

    @Test
    func failedRecordsBalanceRefreshDoesNotLoadHistoryOrHideTheError() async {
        let client = FakeAccountClient()
        client.userError = FakeAccountClient.Failure.requested
        let store = WalletManagementStore()

        await store.refresh(client: client, target: .records)

        #expect(client.topUpPageCalls == 0)
        #expect(store.errorMessage != nil)
        #expect(!store.hasLoadedFundingRecords)
    }

    @Test
    func walletStoreUpdatesPreferenceAndCreatesSubscriptionCheckout() async {
        let client = FakeAccountClient()
        let store = WalletManagementStore()
        await store.loadIfNeeded(client: client)

        await store.updateBillingPreference(.walletFirst, client: client)
        #expect(store.billingPreference == .walletFirst)
        #expect(client.preferenceCalls == 1)

        let checkout = await store.createSubscriptionCheckout(.stripe(planID: 3), client: client)
        #expect(checkout == .url(URL(string: "https://pay.example.com/subscription")!))
        #expect(client.subscriptionCheckoutCalls == 1)
        #expect(store.checkoutMessage == "支付完成后请刷新订阅状态")
    }
}

@MainActor
private final class FakeAccountClient: AccountManagementClient {
    enum Failure: Error { case requested }

    var tokenPageCalls = 0
    var userCalls = 0
    var topUpInfoCalls = 0
    var topUpPageCalls = 0
    var subscriptionPlanCalls = 0
    var subscriptionSelfCalls = 0
    var preferenceCalls = 0
    var subscriptionCheckoutCalls = 0
    var revealCalls = 0
    var lastKeyword: String?
    var shouldFailTokenLoad = false
    var tokenLoadError: Error?
    var userDelay: Duration?
    var userError: Error?
    var topUpPageDelay: Duration?
    var subscriptionPlanError: Error?

    func fetchCurrentUser() async throws -> AuthenticatedUser {
        userCalls += 1
        if let userDelay { try await Task.sleep(for: userDelay) }
        if let userError { throw userError }
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
        if let topUpPageDelay { try await Task.sleep(for: topUpPageDelay) }
        return TopUpPage(page: page, pageSize: pageSize, total: 0, items: [])
    }

    func fetchPaymentAmount(_ request: PaymentRequest) async throws -> Double { 10 }

    func createPaymentCheckout(_ request: PaymentRequest) async throws -> PaymentCheckout {
        .url(URL(string: "https://pay.example.com")!)
    }

    func fetchSubscriptionPlans() async throws -> [SubscriptionPlanItem] {
        subscriptionPlanCalls += 1
        if let subscriptionPlanError { throw subscriptionPlanError }
        return [SubscriptionPlanItem(plan: Self.plan)]
    }

    func fetchSubscriptionSelf() async throws -> SubscriptionSelf {
        subscriptionSelfCalls += 1
        return SubscriptionSelf(
            billingPreference: .subscriptionFirst,
            subscriptions: [],
            allSubscriptions: []
        )
    }

    func updateBillingPreference(_ preference: BillingPreference) async throws -> BillingPreference {
        preferenceCalls += 1
        return preference
    }

    func createSubscriptionCheckout(_ request: SubscriptionPaymentRequest) async throws -> PaymentCheckout {
        subscriptionCheckoutCalls += 1
        return .url(URL(string: "https://pay.example.com/subscription")!)
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

    private static let plan = SubscriptionPlan(
        id: 3,
        title: "Pro",
        subtitle: "",
        priceAmount: 29.9,
        currency: "USD",
        durationUnit: "month",
        durationValue: 1,
        customSeconds: 0,
        enabled: true,
        sortOrder: 10,
        stripePriceID: "price_123",
        creemProductID: "product_123",
        maxPurchasePerUser: 2,
        upgradeGroup: "pro",
        totalAmount: 100_000_000,
        quotaResetPeriod: "monthly",
        quotaResetCustomSeconds: 0,
        createdAt: 0,
        updatedAt: 0
    )
}
