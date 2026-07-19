import Foundation
import Observation

enum WalletRefreshTarget {
    case subscriptions
    case recharge
    case records
}

private enum WalletErrorSource {
    case subscriptions
    case recharge
    case records
    case mutation
}

@Observable
@MainActor
final class WalletManagementStore {
    private(set) var user: AuthenticatedUser?
    private(set) var topUpInfo: TopUpInfo?
    private(set) var plans: [SubscriptionPlan] = []
    private(set) var subscriptions: [SubscriptionSummary] = []
    private(set) var allSubscriptions: [SubscriptionSummary] = []
    private(set) var billingPreference: BillingPreference = .subscriptionFirst
    private(set) var records: [TopUpRecord] = []
    private(set) var total = 0
    private(set) var hasLoaded = false
    private(set) var hasLoadedFundingRecords = false
    private var isLoadingOverview = false
    private var isLoadingRecords = false
    private(set) var isMutating = false
    private(set) var requiresAuthentication = false
    private var subscriptionErrorMessage: String?
    private var rechargeErrorMessage: String?
    private var recordsErrorMessage: String?
    private var mutationErrorMessage: String?
    var errorMessage: String? {
        get {
            mutationErrorMessage
                ?? subscriptionErrorMessage
                ?? rechargeErrorMessage
                ?? recordsErrorMessage
        }
        set { mutationErrorMessage = newValue }
    }
    var checkoutMessage: String?
    private(set) var estimatedPaymentAmount: Double?
    private(set) var estimatedPaymentRequest: PaymentRequest?
    var page = 1
    let pageSize = 20

    var pageCount: Int { max(Int(ceil(Double(total) / Double(pageSize))), 1) }
    var isLoading: Bool { isLoadingOverview || isLoadingRecords }

    private var generation = 0

    func loadIfNeeded(client: any AccountManagementClient) async {
        guard !hasLoaded else { return }
        _ = await load(client: client, target: .subscriptions)
    }

    func refresh(client: any AccountManagementClient, target: WalletRefreshTarget) async {
        let operationGeneration = generation
        let overviewSucceeded = await load(client: client, target: target)
        guard overviewSucceeded, generation == operationGeneration else { return }
        if target == .records {
            await loadRecords(client: client, expectedGeneration: operationGeneration)
        }
    }

    func loadFundingRecordsIfNeeded(client: any AccountManagementClient) async {
        guard !hasLoadedFundingRecords else { return }
        await loadRecords(client: client)
    }

    func goToPage(_ newPage: Int, client: any AccountManagementClient) async {
        let clamped = min(max(newPage, 1), pageCount)
        guard clamped != page else { return }
        page = clamped
        await loadRecords(client: client)
    }

    func createCheckout(
        _ request: PaymentRequest,
        client: any AccountManagementClient
    ) async -> PaymentCheckout? {
        guard !isMutating else { return nil }
        guard estimatedPaymentRequest == request, estimatedPaymentAmount != nil else {
            errorMessage = "请先确认预计支付金额"
            return nil
        }
        let operationGeneration = generation
        isMutating = true
        defer {
            if generation == operationGeneration { isMutating = false }
        }
        do {
            let checkout = try await client.createPaymentCheckout(request)
            guard generation == operationGeneration else { return nil }
            errorMessage = nil
            checkoutMessage = "支付完成后请刷新余额与账单"
            return checkout
        } catch {
            guard generation == operationGeneration else { return nil }
            record(error)
            return nil
        }
    }

    func createSubscriptionCheckout(
        _ request: SubscriptionPaymentRequest,
        client: any AccountManagementClient
    ) async -> PaymentCheckout? {
        guard !isMutating else { return nil }
        let operationGeneration = generation
        isMutating = true
        defer {
            if generation == operationGeneration { isMutating = false }
        }
        do {
            let checkout = try await client.createSubscriptionCheckout(request)
            guard generation == operationGeneration else { return nil }
            errorMessage = nil
            checkoutMessage = "支付完成后请刷新订阅状态"
            return checkout
        } catch {
            guard generation == operationGeneration else { return nil }
            record(error)
            return nil
        }
    }

    func updateBillingPreference(
        _ preference: BillingPreference,
        client: any AccountManagementClient
    ) async {
        guard !isMutating, preference != billingPreference else { return }
        let operationGeneration = generation
        isMutating = true
        defer {
            if generation == operationGeneration { isMutating = false }
        }
        do {
            let loadedPreference = try await client.updateBillingPreference(preference)
            guard generation == operationGeneration else { return }
            billingPreference = loadedPreference
            errorMessage = nil
        } catch {
            guard generation == operationGeneration else { return }
            record(error)
        }
    }

    func purchaseCount(for planID: Int) -> Int {
        allSubscriptions.reduce(into: 0) { count, summary in
            if summary.subscription.planID == planID { count += 1 }
        }
    }

    func estimatePayment(
        _ request: PaymentRequest,
        client: any AccountManagementClient
    ) async {
        guard !isMutating else { return }
        let operationGeneration = generation
        isMutating = true
        defer {
            if generation == operationGeneration { isMutating = false }
        }
        do {
            let amount = try await client.fetchPaymentAmount(request)
            guard generation == operationGeneration else { return }
            estimatedPaymentAmount = amount
            estimatedPaymentRequest = request
            errorMessage = nil
        } catch {
            guard generation == operationGeneration else { return }
            clearPaymentEstimate()
            record(error)
        }
    }

    func setLocalPaymentEstimate(_ amount: Double, for request: PaymentRequest) {
        guard amount.isFinite, amount >= 0 else {
            clearPaymentEstimate()
            return
        }
        estimatedPaymentAmount = amount
        estimatedPaymentRequest = request
        errorMessage = nil
    }

    func clearPaymentEstimate() {
        estimatedPaymentAmount = nil
        estimatedPaymentRequest = nil
    }

    func reset() {
        generation &+= 1
        user = nil
        topUpInfo = nil
        plans = []
        subscriptions = []
        allSubscriptions = []
        billingPreference = .subscriptionFirst
        records = []
        total = 0
        page = 1
        hasLoaded = false
        hasLoadedFundingRecords = false
        isLoadingOverview = false
        isLoadingRecords = false
        isMutating = false
        requiresAuthentication = false
        subscriptionErrorMessage = nil
        rechargeErrorMessage = nil
        recordsErrorMessage = nil
        mutationErrorMessage = nil
        checkoutMessage = nil
        clearPaymentEstimate()
    }

    private func load(
        client: any AccountManagementClient,
        target: WalletRefreshTarget
    ) async -> Bool {
        guard !isLoadingOverview else { return false }
        let operationGeneration = generation
        let errorSource: WalletErrorSource = switch target {
        case .subscriptions: .subscriptions
        case .recharge: .recharge
        case .records: .records
        }
        isLoadingOverview = true
        defer {
            if generation == operationGeneration { isLoadingOverview = false }
        }
        do {
            let loadedUser = try await client.fetchCurrentUser()
            guard generation == operationGeneration else { return false }

            switch target {
            case .subscriptions:
                let loadedInfo = try await client.fetchTopUpInfo()
                guard generation == operationGeneration else { return false }
                let loadedPlans = try await client.fetchSubscriptionPlans()
                guard generation == operationGeneration else { return false }
                let loadedSubscriptions = try await client.fetchSubscriptionSelf()
                guard generation == operationGeneration else { return false }

                topUpInfo = loadedInfo
                plans = loadedPlans.map(\.plan)
                subscriptions = loadedSubscriptions.subscriptions
                allSubscriptions = loadedSubscriptions.allSubscriptions
                billingPreference = loadedSubscriptions.billingPreference
                hasLoaded = true
            case .recharge:
                let loadedInfo = try await client.fetchTopUpInfo()
                guard generation == operationGeneration else { return false }
                topUpInfo = loadedInfo
            case .records:
                break
            }

            clearPaymentEstimate()
            user = loadedUser
            clearError(errorSource)
            return true
        } catch {
            guard generation == operationGeneration else { return false }
            record(error, source: errorSource)
            return false
        }
    }

    private func loadRecords(
        client: any AccountManagementClient,
        expectedGeneration: Int? = nil
    ) async {
        guard !isLoadingRecords else { return }
        let operationGeneration = expectedGeneration ?? generation
        guard generation == operationGeneration else { return }
        isLoadingRecords = true
        defer {
            if generation == operationGeneration { isLoadingRecords = false }
        }
        do {
            let loadedPage = try await client.fetchTopUps(page: page, pageSize: pageSize)
            guard generation == operationGeneration else { return }
            records = loadedPage.items
            total = loadedPage.total
            page = loadedPage.page
            hasLoadedFundingRecords = true
            clearError(.records)
        } catch {
            guard generation == operationGeneration else { return }
            record(error, source: .records)
        }
    }

    private func clearError(_ source: WalletErrorSource) {
        switch source {
        case .subscriptions: subscriptionErrorMessage = nil
        case .recharge: rechargeErrorMessage = nil
        case .records: recordsErrorMessage = nil
        case .mutation: mutationErrorMessage = nil
        }
    }

    private func record(_ error: Error, source: WalletErrorSource = .mutation) {
        switch source {
        case .subscriptions: subscriptionErrorMessage = error.localizedDescription
        case .recharge: rechargeErrorMessage = error.localizedDescription
        case .records: recordsErrorMessage = error.localizedDescription
        case .mutation: mutationErrorMessage = error.localizedDescription
        }
        if let apiError = error as? APIClient.APIError, case .unauthorized = apiError {
            requiresAuthentication = true
        }
    }
}
