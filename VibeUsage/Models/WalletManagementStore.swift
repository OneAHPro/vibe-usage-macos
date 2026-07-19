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
    var errorMessage: String?
    var checkoutMessage: String?
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
        await load(client: client)
    }

    func createCheckout(
        _ request: PaymentRequest,
        client: any AccountManagementClient
    ) async -> PaymentCheckout? {
        guard !isMutating else { return nil }
        isMutating = true
        defer { isMutating = false }
        do {
            let checkout = try await client.createPaymentCheckout(request)
            errorMessage = nil
            checkoutMessage = "支付完成后请刷新余额与账单"
            return checkout
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
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
        errorMessage = nil
        checkoutMessage = nil
    }

    private func load(client: any AccountManagementClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedUser = try await client.fetchCurrentUser()
            let loadedInfo = try await client.fetchTopUpInfo()
            let loadedPage = try await client.fetchTopUps(page: page, pageSize: pageSize)
            user = loadedUser
            topUpInfo = loadedInfo
            records = loadedPage.items
            total = loadedPage.total
            page = loadedPage.page
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
