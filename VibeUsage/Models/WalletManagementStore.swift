import Foundation
import Observation

@Observable
@MainActor
final class WalletManagementStore {
    private(set) var user: AuthenticatedUser?
    private(set) var topUpInfo: TopUpInfo?
    private(set) var records: [TopUpRecord] = []
    private(set) var total = 0
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var requiresAuthentication = false
    var errorMessage: String?
    var checkoutMessage: String?
    private(set) var estimatedPaymentAmount: Double?
    private(set) var estimatedPaymentRequest: PaymentRequest?
    var page = 1
    let pageSize = 20

    var pageCount: Int { max(Int(ceil(Double(total) / Double(pageSize))), 1) }

    func loadIfNeeded(client: any AccountManagementClient) async {
        guard !hasLoaded else { return }
        await load(client: client)
    }

    func refresh(client: any AccountManagementClient) async {
        await load(client: client)
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
        isMutating = true
        defer { isMutating = false }
        do {
            let checkout = try await client.createPaymentCheckout(request)
            errorMessage = nil
            requiresAuthentication = false
            checkoutMessage = "支付完成后请刷新余额与账单"
            return checkout
        } catch {
            record(error)
            return nil
        }
    }

    func estimatePayment(
        _ request: PaymentRequest,
        client: any AccountManagementClient
    ) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let amount = try await client.fetchPaymentAmount(request)
            estimatedPaymentAmount = amount
            estimatedPaymentRequest = request
            errorMessage = nil
            requiresAuthentication = false
        } catch {
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
        user = nil
        topUpInfo = nil
        records = []
        total = 0
        page = 1
        hasLoaded = false
        isLoading = false
        isMutating = false
        requiresAuthentication = false
        errorMessage = nil
        checkoutMessage = nil
        clearPaymentEstimate()
    }

    private func load(client: any AccountManagementClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedUser = try await client.fetchCurrentUser()
            let loadedInfo = try await client.fetchTopUpInfo()
            let loadedPage = try await client.fetchTopUps(page: page, pageSize: pageSize)
            clearPaymentEstimate()
            user = loadedUser
            topUpInfo = loadedInfo
            records = loadedPage.items
            total = loadedPage.total
            page = loadedPage.page
            hasLoaded = true
            errorMessage = nil
            requiresAuthentication = false
        } catch {
            record(error)
        }
    }

    private func loadRecords(client: any AccountManagementClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedPage = try await client.fetchTopUps(page: page, pageSize: pageSize)
            records = loadedPage.items
            total = loadedPage.total
            page = loadedPage.page
            errorMessage = nil
            requiresAuthentication = false
        } catch {
            record(error)
        }
    }

    private func record(_ error: Error) {
        errorMessage = error.localizedDescription
        if let apiError = error as? APIClient.APIError, case .unauthorized = apiError {
            requiresAuthentication = true
        }
    }
}
