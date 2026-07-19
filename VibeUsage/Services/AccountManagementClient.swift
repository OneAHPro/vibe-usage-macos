import Foundation

@MainActor
protocol AccountManagementClient {
    func fetchCurrentUser() async throws -> AuthenticatedUser
    func fetchTokens(
        page: Int,
        pageSize: Int,
        keyword: String?,
        tokenQuery: String?
    ) async throws -> TokenPage
    func createToken(_ mutation: TokenMutation) async throws
    func updateToken(_ mutation: TokenMutation) async throws
    func setTokenEnabled(id: Int, enabled: Bool) async throws
    func deleteToken(id: Int) async throws
    func revealTokenKey(id: Int) async throws -> String
    func fetchTopUpInfo() async throws -> TopUpInfo
    func fetchTopUps(page: Int, pageSize: Int) async throws -> TopUpPage
    func createPaymentCheckout(_ request: PaymentRequest) async throws -> PaymentCheckout
}

extension AccountManagementClient {
    func fetchTokens(page: Int, pageSize: Int) async throws -> TokenPage {
        try await fetchTokens(
            page: page,
            pageSize: pageSize,
            keyword: nil,
            tokenQuery: nil
        )
    }
}

extension APIClient: AccountManagementClient {
    func fetchTokens(
        page: Int,
        pageSize: Int,
        keyword: String? = nil,
        tokenQuery: String? = nil
    ) async throws -> TokenPage {
        let hasSearch = !(keyword ?? "").isEmpty || !(tokenQuery ?? "").isEmpty
        var items = [
            URLQueryItem(name: "p", value: String(max(page, 1))),
            URLQueryItem(name: "size", value: String(min(max(pageSize, 1), 100))),
        ]
        if hasSearch {
            items.insert(URLQueryItem(name: "keyword", value: keyword ?? ""), at: 0)
            items.insert(URLQueryItem(name: "token", value: tokenQuery ?? ""), at: 1)
        }
        let request = try accountRequest(
            path: hasSearch ? "/api/token/search" : "/api/token/",
            queryItems: items
        )
        let envelope: APIEnvelope<TokenPage> = try await send(request: request)
        guard let page = envelope.data else { throw APIError.invalidResponse }
        return page
    }

    func createToken(_ mutation: TokenMutation) async throws {
        let body = try JSONEncoder().encode(mutation)
        let _: APIEnvelope<EmptyPayload> = try await send(
            path: "/api/token/",
            method: "POST",
            body: body
        )
    }

    func updateToken(_ mutation: TokenMutation) async throws {
        let body = try JSONEncoder().encode(mutation)
        let _: APIEnvelope<EmptyPayload> = try await send(
            path: "/api/token/",
            method: "PUT",
            body: body
        )
    }

    func setTokenEnabled(id: Int, enabled: Bool) async throws {
        let body = try JSONEncoder().encode([
            "id": id,
            "status": enabled ? 1 : 2,
        ])
        let _: APIEnvelope<EmptyPayload> = try await send(
            path: "/api/token/?status_only=true",
            method: "PUT",
            body: body
        )
    }

    func deleteToken(id: Int) async throws {
        let _: APIEnvelope<EmptyPayload> = try await send(
            path: "/api/token/\(id)",
            method: "DELETE"
        )
    }

    func revealTokenKey(id: Int) async throws -> String {
        let envelope: APIEnvelope<TokenKeyPayload> = try await send(
            path: "/api/token/\(id)/key",
            method: "POST"
        )
        guard let key = envelope.data?.key, !key.isEmpty else {
            throw APIError.invalidResponse
        }
        return key
    }

    func fetchTopUpInfo() async throws -> TopUpInfo {
        let envelope: APIEnvelope<TopUpInfo> = try await send(path: "/api/user/topup/info")
        guard let info = envelope.data else { throw APIError.invalidResponse }
        return info
    }

    func fetchTopUps(page: Int, pageSize: Int) async throws -> TopUpPage {
        let request = try accountRequest(
            path: "/api/user/topup/self",
            queryItems: [
                URLQueryItem(name: "p", value: String(max(page, 1))),
                URLQueryItem(name: "page_size", value: String(min(max(pageSize, 1), 100))),
            ]
        )
        let envelope: APIEnvelope<TopUpPage> = try await send(request: request)
        guard let page = envelope.data else { throw APIError.invalidResponse }
        return page
    }

    func createPaymentCheckout(_ paymentRequest: PaymentRequest) async throws -> PaymentCheckout {
        let path: String
        let body: Data
        switch paymentRequest {
        case .epay(let amount, let paymentMethod):
            path = "/api/user/pay"
            body = try JSONEncoder().encode(EpayRequest(amount: amount, paymentMethod: paymentMethod))
        case .stripe(let amount):
            path = "/api/user/stripe/pay"
            body = try JSONEncoder().encode(StripeRequest(amount: amount, paymentMethod: "stripe"))
        case .creem(let productID):
            path = "/api/user/creem/pay"
            body = try JSONEncoder().encode(CreemRequest(productID: productID, paymentMethod: "creem"))
        case .waffo(let amount, let payMethodIndex):
            path = "/api/user/waffo/pay"
            body = try JSONEncoder().encode(WaffoRequest(amount: amount, payMethodIndex: payMethodIndex))
        }

        let request = try accountRequest(path: path, method: "POST", body: body)
        let data = try await sendRaw(request: request)

        switch paymentRequest {
        case .epay:
            let response = try JSONDecoder().decode(EpayResponse.self, from: data)
            try validatePaymentMessage(response.message, fallback: nil)
            guard let action = Self.validCheckoutURL(response.url), let fields = response.data else {
                throw APIError.invalidResponse
            }
            return .form(action: action, fields: fields)
        case .stripe:
            let response = try JSONDecoder().decode(StripeResponse.self, from: data)
            try validatePaymentMessage(response.message, fallback: nil)
            guard let url = Self.validCheckoutURL(response.data?.payLink) else {
                throw APIError.invalidResponse
            }
            return .url(url)
        case .creem:
            let response = try JSONDecoder().decode(CreemResponse.self, from: data)
            try validatePaymentMessage(response.message, fallback: nil)
            guard let url = Self.validCheckoutURL(response.data?.checkoutURL) else {
                throw APIError.invalidResponse
            }
            return .url(url)
        case .waffo:
            let response = try JSONDecoder().decode(WaffoResponse.self, from: data)
            try validatePaymentMessage(response.message, fallback: nil)
            guard let url = Self.validCheckoutURL(response.data?.paymentURL) else {
                throw APIError.invalidResponse
            }
            return .url(url)
        }
    }

    private func accountRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let userID {
            request.setValue(String(userID), forHTTPHeaderField: "New-Api-User")
        }
        return request
    }

    private func validatePaymentMessage(_ message: String, fallback: String?) throws {
        guard message.lowercased() == "success" else {
            throw APIError.server(fallback ?? (message.isEmpty ? "创建支付订单失败" : message))
        }
    }

    private static func validCheckoutURL(_ value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }
}

private struct TokenKeyPayload: Decodable {
    let key: String
}

private struct EpayRequest: Encodable {
    let amount: Int64
    let paymentMethod: String

    enum CodingKeys: String, CodingKey {
        case amount
        case paymentMethod = "payment_method"
    }
}

private struct StripeRequest: Encodable {
    let amount: Int64
    let paymentMethod: String

    enum CodingKeys: String, CodingKey {
        case amount
        case paymentMethod = "payment_method"
    }
}

private struct CreemRequest: Encodable {
    let productID: String
    let paymentMethod: String

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case paymentMethod = "payment_method"
    }
}

private struct WaffoRequest: Encodable {
    let amount: Int64
    let payMethodIndex: Int?

    enum CodingKeys: String, CodingKey {
        case amount
        case payMethodIndex = "pay_method_index"
    }
}

private struct EpayResponse: Decodable {
    let message: String
    let data: [String: String]?
    let url: String?
}

private struct StripeResponse: Decodable {
    struct Payload: Decodable {
        let payLink: String?

        enum CodingKeys: String, CodingKey {
            case payLink = "pay_link"
        }
    }

    let message: String
    let data: Payload?
}

private struct CreemResponse: Decodable {
    struct Payload: Decodable {
        let checkoutURL: String?

        enum CodingKeys: String, CodingKey {
            case checkoutURL = "checkout_url"
        }
    }

    let message: String
    let data: Payload?
}

private struct WaffoResponse: Decodable {
    struct Payload: Decodable {
        let paymentURL: String?

        enum CodingKeys: String, CodingKey {
            case paymentURL = "payment_url"
        }
    }

    let message: String
    let data: Payload?
}
