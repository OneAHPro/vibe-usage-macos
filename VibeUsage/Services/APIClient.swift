import Foundation

struct AuthenticatedUser: Codable, Equatable, Sendable {
    let id: Int
    let username: String
    let displayName: String?
    let role: Int
    let status: Int
    let group: String
    let usedQuota: Int?
    let requestCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, role, status, group
        case displayName = "display_name"
        case usedQuota = "used_quota"
        case requestCount = "request_count"
    }
}

enum LoginOutcome: Equatable, Sendable {
    case authenticated(AuthenticatedUser)
    case requiresTwoFactor
}

private struct APIEnvelope<Payload: Decodable>: Decodable {
    let success: Bool
    let message: String
    let data: Payload?
}

private struct LoginPayload: Decodable {
    let requireTwoFactor: Bool?
    let id: Int?
    let username: String?
    let displayName: String?
    let role: Int?
    let status: Int?
    let group: String?
    let usedQuota: Int?
    let requestCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, role, status, group
        case requireTwoFactor = "require_2fa"
        case displayName = "display_name"
        case usedQuota = "used_quota"
        case requestCount = "request_count"
    }

    var authenticatedUser: AuthenticatedUser? {
        guard let id, let username, let role, let status, let group else { return nil }
        return AuthenticatedUser(
            id: id,
            username: username,
            displayName: displayName,
            role: role,
            status: status,
            group: group,
            usedQuota: usedQuota,
            requestCount: requestCount
        )
    }
}

private struct EmptyPayload: Decodable {}

private struct RemoteStatus: Decodable, Sendable {
    let quotaPerUnit: Double

    enum CodingKeys: String, CodingKey {
        case quotaPerUnit = "quota_per_unit"
    }
}

/// HTTP client for the new system. URLSession owns the HttpOnly session cookie;
/// the app only persists the user id required by New-Api-User.
struct APIClient: Sendable {
    let baseURL: String
    let userID: Int?
    let session: URLSession

    init(baseURL: String, userID: Int? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.userID = userID
        self.session = session
    }

    func login(username: String, password: String) async throws -> LoginOutcome {
        let body = try JSONEncoder().encode(["username": username, "password": password])
        let envelope: APIEnvelope<LoginPayload> = try await send(
            path: "/api/user/login",
            method: "POST",
            body: body,
            authenticated: false
        )
        guard let payload = envelope.data else { throw APIError.invalidResponse }
        if payload.requireTwoFactor == true {
            return .requiresTwoFactor
        }
        guard let user = payload.authenticatedUser else { throw APIError.invalidResponse }
        return .authenticated(user)
    }

    func verifyTwoFactor(code: String) async throws -> AuthenticatedUser {
        let body = try JSONEncoder().encode(["code": code])
        let envelope: APIEnvelope<LoginPayload> = try await send(
            path: "/api/user/login/2fa",
            method: "POST",
            body: body,
            authenticated: false
        )
        guard let user = envelope.data?.authenticatedUser else { throw APIError.invalidResponse }
        return user
    }

    func fetchCurrentUser() async throws -> AuthenticatedUser {
        let envelope: APIEnvelope<AuthenticatedUser> = try await send(path: "/api/user/self")
        guard let user = envelope.data else { throw APIError.invalidResponse }
        return user
    }

    func logout() async throws {
        let _: APIEnvelope<EmptyPayload> = try await send(path: "/api/user/logout")
    }

    func fetchLeaderboard() async throws -> LeaderboardData {
        let envelope: APIEnvelope<LeaderboardData> = try await send(
            path: "/api/user/leaderboard"
        )
        guard let data = envelope.data else { throw APIError.invalidResponse }
        return data
    }

    /// Fetch usage buckets for the dashboard.
    func fetchUsage(range: UsageQueryRange) async throws -> UsageResponse {
        guard var components = URLComponents(string: "\(baseURL)/api/desktop/usage") else {
            throw APIError.invalidURL
        }
        var queryItems = range.queryItems
        queryItems.append(URLQueryItem(name: "tz", value: TimeZone.current.identifier))
        components.queryItems = queryItems
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let userID {
            request.setValue(String(userID), forHTTPHeaderField: "New-Api-User")
        }
        request.timeoutInterval = 30

        let envelope: APIEnvelope<UsageResponse> = try await send(request: request)
        guard let usage = envelope.data else { throw APIError.invalidResponse }
        return usage
    }

    func fetchQuotaPerUnit() async -> Double {
        do {
            let envelope: APIEnvelope<RemoteStatus> = try await send(
                path: "/api/status",
                authenticated: false
            )
            if let value = envelope.data?.quotaPerUnit, value > 0 {
                return value
            }
        } catch {
            debugLog("[APIClient] quota_per_unit fallback: \(error.localizedDescription)")
        }
        return 500_000
    }

    /// Fetch hour-level buckets for longer dashboard ranges. The usage API
    /// automatically switches multi-day requests to daily aggregation, so we
    /// request one exact day at a time and keep concurrency bounded.
    func fetchHourlyBuckets(ranges: [UsageQueryRange], batchSize: Int = 6) async -> [UsageBucket] {
        guard !ranges.isEmpty else { return [] }
        var collected: [UsageBucket] = []
        let safeBatchSize = max(batchSize, 1)

        for start in stride(from: 0, to: ranges.count, by: safeBatchSize) {
            let end = min(start + safeBatchSize, ranges.count)
            let batch = Array(ranges[start..<end])
            let batchBuckets = await withTaskGroup(of: [UsageBucket].self) { group in
                for range in batch {
                    group.addTask {
                        (try? await fetchUsage(range: range).buckets) ?? []
                    }
                }

                var result: [UsageBucket] = []
                for await buckets in group {
                    result.append(contentsOf: buckets)
                }
                return result
            }
            collected.append(contentsOf: batchBuckets)
        }

        var unique: [String: UsageBucket] = [:]
        for bucket in collected {
            unique[bucket.id] = bucket
        }
        return unique.values.sorted { $0.bucketStart < $1.bucketStart }
    }

    private func send<Payload: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> APIEnvelope<Payload> {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let userID {
            request.setValue(String(userID), forHTTPHeaderField: "New-Api-User")
        }
        return try await send(request: request)
    }

    private func send<Payload: Decodable>(request: URLRequest) async throws -> APIEnvelope<Payload> {
        debugLog("[APIClient] \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited(retryAfter: Self.retryAfterDate(from: httpResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<Payload>.self, from: data)
        guard envelope.success else {
            throw APIError.server(envelope.message.isEmpty ? "服务器请求失败" : envelope.message)
        }
        return envelope
    }

    private static func retryAfterDate(
        from response: HTTPURLResponse,
        now: Date = Date()
    ) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }

        if let seconds = TimeInterval(raw), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: raw)
    }

    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case unauthorized
        case rateLimited(retryAfter: Date?)
        case httpError(Int)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "URL 无效"
            case .invalidResponse: "服务器响应异常"
            case .unauthorized: "登录已过期，请重新登录"
            case .rateLimited: "请求过于频繁，请稍后再试"
            case .httpError(let code): "HTTP 错误 \(code)"
            case .server(let message): message
            }
        }
    }
}

enum UsageQueryRange: Sendable {
    case days(Int)
    case from(Date)
    case custom(from: Date, to: Date)
    case exact(from: Date, to: Date)
    case all

    var isAll: Bool {
        if case .all = self { return true }
        return false
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .days(let days):
            [URLQueryItem(name: "days", value: String(days))]
        case .from(let from):
            [URLQueryItem(name: "from", value: Self.isoString(from))]
        case .custom(let from, let to):
            [
                URLQueryItem(name: "from", value: Self.dateString(from)),
                URLQueryItem(name: "to", value: Self.dateString(to)),
            ]
        case .exact(let from, let to):
            [
                URLQueryItem(name: "from", value: Self.isoString(from)),
                URLQueryItem(name: "to", value: Self.isoString(to)),
            ]
        case .all:
            [
                URLQueryItem(name: "all", value: "true"),
                URLQueryItem(name: "from", value: Self.isoString(Date(timeIntervalSince1970: 0))),
            ]
        }
    }

    func dateInterval(now: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .days(let days):
            return DateInterval(start: now.addingTimeInterval(-Double(days) * 86_400), end: now)
        case .from(let from):
            return DateInterval(start: min(from, now), end: now)
        case .custom(let from, let to):
            let lower = calendar.startOfDay(for: min(from, to))
            let upperDay = calendar.startOfDay(for: max(from, to))
            let inclusiveUpper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? now
            return DateInterval(start: min(lower, now), end: min(inclusiveUpper, now))
        case .exact(let from, let to):
            return DateInterval(start: min(from, to), end: max(from, to))
        case .all:
            return DateInterval(start: Date(timeIntervalSince1970: 0), end: now)
        }
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Device authorization flow (unauthenticated)

struct DeviceCodeResponse: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let verificationUriComplete: String
    let expiresIn: Int
    let interval: Int
}

struct DevicePollResponse: Decodable, Sendable {
    let apiKey: String?
    let apiUrl: String?
    let error: String?
}

enum DeviceFlowError: LocalizedError {
    case denied
    case expired
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .denied: "你拒绝了链接请求。"
        case .expired: "验证码已过期，请重新登录。"
        case .network(let msg): "网络错误：\(msg)"
        case .server(let msg): "服务端错误：\(msg)"
        }
    }
}

func requestDeviceCode(baseURL: String, clientName: String, hostname: String?) async throws -> DeviceCodeResponse {
    guard let url = URL(string: "\(baseURL)/api/usage/device/code") else {
        throw APIClient.APIError.invalidURL
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 15
    var body: [String: String] = ["clientName": clientName]
    if let hostname { body["hostname"] = hostname }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw APIClient.APIError.invalidResponse
    }
    guard http.statusCode == 200 else {
        throw APIClient.APIError.httpError(http.statusCode)
    }
    return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
}

func pollDeviceCode(baseURL: String, deviceCode: String) async throws -> DevicePollResponse {
    guard let url = URL(string: "\(baseURL)/api/usage/device/poll") else {
        throw APIClient.APIError.invalidURL
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 15
    req.httpBody = try JSONSerialization.data(withJSONObject: ["deviceCode": deviceCode])

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw APIClient.APIError.invalidResponse
    }
    // 200 covers success + pending/denied/expired (RFC 8628 style).
    // 410 is "already delivered, never replay".
    if http.statusCode == 200 || http.statusCode == 410 {
        return try JSONDecoder().decode(DevicePollResponse.self, from: data)
    }
    throw APIClient.APIError.httpError(http.statusCode)
}
