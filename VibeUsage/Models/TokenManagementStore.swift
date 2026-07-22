import Foundation
import Observation

@Observable
@MainActor
final class TokenManagementStore {
    private(set) var tokens: [TokenRecord] = []
    private(set) var total = 0
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var requiresAuthentication = false
    var errorMessage: String?
    var page = 1
    let pageSize = 20
    var searchText = ""
    var tokenSearchText = ""

    var pageCount: Int { max(Int(ceil(Double(total) / Double(pageSize))), 1) }
    var enabledCount: Int { tokens.count(where: { $0.status == 1 }) }
    var finiteQuotaTotal: Int {
        tokens.filter { !$0.unlimitedQuota }.reduce(0) { $0 + $1.remainQuota }
    }

    func loadIfNeeded(client: any AccountManagementClient) async {
        guard !hasLoaded else { return }
        await load(client: client)
    }

    func refresh(client: any AccountManagementClient) async {
        await load(client: client)
    }

    func submitSearch(client: any AccountManagementClient) async {
        page = 1
        await load(client: client)
    }

    func goToPage(_ newPage: Int, client: any AccountManagementClient) async {
        let clamped = min(max(newPage, 1), pageCount)
        guard clamped != page else { return }
        page = clamped
        await load(client: client)
    }

    func create(_ mutation: TokenMutation, client: any AccountManagementClient) async -> Bool {
        await performMutation(client: client) {
            try await client.createToken(mutation)
        }
    }

    func update(_ mutation: TokenMutation, client: any AccountManagementClient) async -> Bool {
        await performMutation(client: client) {
            try await client.updateToken(mutation)
        }
    }

    func setEnabled(_ enabled: Bool, id: Int, client: any AccountManagementClient) async -> Bool {
        await performMutation(client: client) {
            try await client.setTokenEnabled(id: id, enabled: enabled)
        }
    }

    func delete(id: Int, client: any AccountManagementClient) async -> Bool {
        await performMutation(client: client) {
            try await client.deleteToken(id: id)
        }
    }

    func revealTokenKey(
        id: Int,
        client: any AccountManagementClient,
        consume: (String) -> Void
    ) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let key = try await client.revealTokenKey(id: id)
            consume(key)
            errorMessage = nil
            requiresAuthentication = false
        } catch {
            record(error)
        }
    }

    func reset() {
        tokens = []
        total = 0
        page = 1
        searchText = ""
        tokenSearchText = ""
        errorMessage = nil
        hasLoaded = false
        isLoading = false
        isMutating = false
        requiresAuthentication = false
    }

    private func load(client: any AccountManagementClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.fetchTokens(
                page: page,
                pageSize: pageSize,
                keyword: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                tokenQuery: tokenSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            tokens = response.items
            total = response.total
            page = response.page
            hasLoaded = true
            errorMessage = nil
            requiresAuthentication = false
        } catch {
            record(error)
        }
    }

    private func performMutation(
        client: any AccountManagementClient,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true
        defer { isMutating = false }
        do {
            try await operation()
            errorMessage = nil
            requiresAuthentication = false
            await load(client: client)
            return true
        } catch {
            record(error)
            return false
        }
    }

    private func record(_ error: Error) {
        errorMessage = error.localizedDescription
        if let apiError = error as? APIClient.APIError, case .unauthorized = apiError {
            requiresAuthentication = true
        }
    }
}
