import Foundation
import Testing
@testable import VibeUsage

@Suite(.serialized)
struct APIClientTests {
    @Test
    func loginReturnsTwoFactorRequirement() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/user/login")
            #expect(request.httpMethod == "POST")
            let body = try requestBody(from: request)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(object["username"] == "xuande")
            #expect(object["password"] == "secret")
            return response(
                for: request,
                body: #"{"success":true,"message":"需要二次验证","data":{"require_2fa":true}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", session: session)

        let outcome = try await client.login(username: "xuande", password: "secret")

        #expect(outcome == .requiresTwoFactor)
    }

    @Test
    func verifyTwoFactorReturnsAuthenticatedUser() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/user/login/2fa")
            let body = try requestBody(from: request)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(object["code"] == "381427")
            return response(
                for: request,
                body: #"{"success":true,"message":"","data":{"id":7,"username":"xuande","display_name":"徐安","role":1,"status":1,"group":"pro","quota":4250000,"used_quota":750000,"request_count":321}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", session: session)

        let user = try await client.verifyTwoFactor(code: "381427")

        #expect(user.id == 7)
        #expect(user.username == "xuande")
        #expect(user.displayName == "徐安")
        #expect(user.usedQuota == 750_000)
        #expect(user.requestCount == 321)
    }

    @Test
    func fetchUsageUsesDesktopEndpointAndUserHeader() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/desktop/usage")
            #expect(request.url?.query?.contains("days=7") == true)
            #expect(request.value(forHTTPHeaderField: "New-Api-User") == "7")
            return response(
                for: request,
                body: #"{"success":true,"message":"","data":{"buckets":[{"source":"mac","model":"gpt-5.6-sol","project":"pro","hostname":"api.anhepro.com","bucketStart":"2026-07-16T01:00:00Z","inputTokens":110,"outputTokens":30,"cacheCreationInputTokens":10,"cachedInputTokens":60,"reasoningOutputTokens":0,"totalTokens":210,"estimatedCost":1.5}],"sessions":[],"recentRequests":[{"id":991,"createdAt":"2026-07-16T01:32:00Z","source":"new-api","model":"gpt-5.6-sol","project":"pro","inputTokens":110,"outputTokens":30,"cachedInputTokens":60,"reasoningOutputTokens":0,"totalTokens":200,"estimatedCost":1.5,"firstResponseTimeMs":2400,"reasoningEffort":"High"}],"hasAnyData":true}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        let usage = try await client.fetchUsage(range: .days(7))

        #expect(usage.hasAnyData)
        #expect(usage.buckets.count == 1)
        #expect(usage.buckets[0].computedTotal == 210)
        #expect(usage.buckets[0].estimatedCost == 1.5)
        #expect(usage.recentRequests?.count == 1)
        let request = try #require(usage.recentRequests?.first)
        #expect(request.id == 991)
        #expect(request.model == "gpt-5.6-sol")
        #expect(request.firstResponseTimeMs == 2_400)
        #expect(request.outputTokens == 30)
        #expect(request.reasoningEffort == "High")
        #expect(usage.coverage == nil)
    }

    @Test
    func fetchUsageDecodesCoverageGranularity() async throws {
        let session = makeSession { request in
            response(
                for: request,
                body: #"{"success":true,"message":"","data":{"buckets":[],"sessions":[],"recentRequests":[],"summary":{"estimatedCost":0,"inputTokens":0,"outputTokens":0,"cachedInputTokens":0,"cacheCreationInputTokens":0,"reasoningOutputTokens":0,"totalTokens":0,"requestCount":0},"coverage":{"requestedStart":"2026-06-19T00:38:47Z","requestedEnd":"2026-07-19T00:38:47Z","dataStart":"2026-06-20T11:34:18Z","dataEnd":"2026-07-19T00:37:00Z","complete":false,"granularity":"day"},"hasAnyData":false}}"#
            )
        }
        let client = APIClient(
            baseURL: "https://api.anhepro.com",
            userID: 7,
            session: session
        )

        let usage = try await client.fetchUsage(range: .days(30))

        #expect(usage.coverage?.granularity == .day)
        #expect(usage.coverage?.complete == false)
        #expect(usage.coverage?.requestedStart == "2026-06-19T00:38:47Z")
        #expect(usage.coverage?.dataStart == "2026-06-20T11:34:18Z")
    }

    @Test
    func fetchUsagePreservesUnknownCoverageGranularity() async throws {
        let session = makeSession { request in
            response(
                for: request,
                body: #"{"success":true,"message":"","data":{"buckets":[],"sessions":[],"coverage":{"requestedStart":null,"requestedEnd":null,"dataStart":null,"dataEnd":null,"complete":true,"granularity":"quarter"},"hasAnyData":false}}"#
            )
        }
        let client = APIClient(
            baseURL: "https://api.anhepro.com",
            userID: 7,
            session: session
        )

        let usage = try await client.fetchUsage(range: .all)

        #expect(usage.coverage?.granularity == .unknown("quarter"))
    }

    @Test
    func allRangeRequestsTheUsersCompleteHistory() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/desktop/usage")
            let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(query["all"] == "true")
            #expect(query["from"] == "1970-01-01T00:00:00.000Z")
            return response(
                for: request,
                body: #"{"success":true,"message":"","data":{"buckets":[],"sessions":[],"hasAnyData":false}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        let usage = try await client.fetchUsage(range: .all)

        #expect(!usage.hasAnyData)
        #expect(usage.recentRequests == nil)
    }

    @Test
    func currentUserUsesSavedUserHeader() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/user/self")
            #expect(request.value(forHTTPHeaderField: "New-Api-User") == "7")
            return response(
                for: request,
                body: #"{"success":true,"message":"","data":{"id":7,"username":"xuande","display_name":"徐安","role":1,"status":1,"group":"pro","quota":4250000,"used_quota":750000,"request_count":321}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        let user = try await client.fetchCurrentUser()

        #expect(user.username == "xuande")
        #expect(user.quota == 4_250_000)
        #expect(user.usedQuota == 750_000)
        #expect(user.requestCount == 321)
    }

    @Test
    func missingDesktopSnapshotDoesNotRequestRawLogs() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/desktop/usage")
            return response(
                for: request,
                body: #"{"error":{"message":"Invalid URL"}}"#,
                status: 404
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        do {
            _ = try await client.fetchUsage(range: .days(1))
            Issue.record("Expected the snapshot request to fail")
        } catch APIClient.APIError.httpError(let status) {
            #expect(status == 404)
        }
    }

    @Test
    func rateLimitCarriesRetryAfterDeadline() async throws {
        let before = Date()
        let session = makeSession { request in
            response(
                for: request,
                body: "{}",
                status: 429,
                headers: ["Retry-After": "90"]
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        do {
            _ = try await client.fetchLeaderboard()
            Issue.record("Expected a rate-limit error")
        } catch APIClient.APIError.rateLimited(let retryAfter) {
            let deadline = try #require(retryAfter)
            #expect(deadline.timeIntervalSince(before) >= 89)
            #expect(deadline.timeIntervalSince(before) <= 91)
        }
    }

    @Test
    func fetchLeaderboardUsesAuthenticatedNewSystemEndpoint() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/user/leaderboard")
            #expect(request.value(forHTTPHeaderField: "New-Api-User") == "7")
            return response(
                for: request,
                body: #"{"success":true,"message":"","data":{"token_total_top":[],"token_daily_top":[],"quota_total_top":[],"quota_daily_top":[],"my_daily_quota_rank":null,"quota_yesterday_top":[],"my_yesterday_quota_rank":null,"invite_reward_top":[]}}"#
            )
        }
        let client = APIClient(
            baseURL: "https://api.anhepro.com",
            userID: 7,
            session: session
        )

        let leaderboard = try await client.fetchLeaderboard()

        #expect(leaderboard.tokenTotalTop.isEmpty)
    }

    @Test
    func tokenListAndSearchUseAuthenticatedPaginationContracts() async throws {
        let recorder = TestRequestRecorder()
        let session = makeSession { request in
            let call = recorder.append(request)
            #expect(request.value(forHTTPHeaderField: "New-Api-User") == "7")
            let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if call == 1 {
                #expect(request.url?.path == "/api/token")
                #expect(query == ["p": "1", "size": "20"])
            } else {
                #expect(request.url?.path == "/api/token/search")
                #expect(query["keyword"] == "Codex")
                #expect(query["token"] == "abcd")
                #expect(query["p"] == "2")
                #expect(query["size"] == "20")
            }
            return response(
                for: request,
                body: #"{"success":true,"message":"","data":{"page":1,"page_size":20,"total":0,"items":[]}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        _ = try await client.fetchTokens(page: 1, pageSize: 20)
        _ = try await client.fetchTokens(
            page: 2,
            pageSize: 20,
            keyword: "Codex",
            tokenQuery: "abcd"
        )

        #expect(recorder.requests.count == 2)
    }

    @Test
    func tokenMutationsUseExpectedMethodsBodiesAndPaths() async throws {
        let recorder = TestRequestRecorder()
        let session = makeSession { request in
            _ = recorder.append(request)
            if request.url?.path == "/api/token/9/key" {
                return response(
                    for: request,
                    body: #"{"success":true,"message":"","data":{"key":"secret-key"}}"#
                )
            }
            return response(for: request, body: #"{"success":true,"message":""}"#)
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)
        let mutation = TokenMutation(
            id: 9,
            name: "Codex",
            expiredTime: -1,
            remainQuota: 1_000_000,
            unlimitedQuota: false,
            modelLimitsEnabled: true,
            modelLimits: "gpt-5.6-sol",
            allowIPs: "127.0.0.1",
            group: "pro",
            crossGroupRetry: true,
            status: 1
        )

        try await client.createToken(mutation)
        try await client.updateToken(mutation)
        try await client.setTokenEnabled(id: 9, enabled: false)
        let key = try await client.revealTokenKey(id: 9)
        try await client.deleteToken(id: 9)

        let requests = recorder.requests
        #expect(requests.map(\.httpMethod) == ["POST", "PUT", "PUT", "POST", "DELETE"])
        #expect(requests.map { $0.url?.path } == [
            "/api/token", "/api/token", "/api/token", "/api/token/9/key", "/api/token/9",
        ])
        #expect(requests[2].url?.query == "status_only=true")
        let statusBody = try requestBody(from: requests[2])
        let statusJSON = try #require(JSONSerialization.jsonObject(with: statusBody) as? [String: Int])
        #expect(statusJSON == ["id": 9, "status": 2])
        #expect(key == "secret-key")
    }

    @Test
    func walletEndpointsDecodeInfoAndHistory() async throws {
        let recorder = TestRequestRecorder()
        let session = makeSession { request in
            let call = recorder.append(request)
            #expect(request.value(forHTTPHeaderField: "New-Api-User") == "7")
            if call == 1 {
                #expect(request.url?.path == "/api/user/topup/info")
                return response(
                    for: request,
                    body: #"{"success":true,"message":"","data":{"enable_online_topup":false,"enable_stripe_topup":false,"enable_creem_topup":false,"enable_waffo_topup":false,"enable_waffo_pancake_topup":false,"amount_options":[],"discount":{}}}"#
                )
            }
            #expect(request.url?.path == "/api/user/topup/self")
            #expect(request.url?.query?.contains("p=1") == true)
            #expect(request.url?.query?.contains("page_size=20") == true)
            return response(
                for: request,
                body: #"{"success":true,"message":"","data":{"page":1,"page_size":20,"total":0,"items":[]}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        let info = try await client.fetchTopUpInfo()
        let page = try await client.fetchTopUps(page: 1, pageSize: 20)

        #expect(!info.enableOnlineTopUp)
        #expect(page.items.isEmpty)
    }

    @Test
    func paymentResponsesMapToValidatedExternalCheckouts() async throws {
        let recorder = TestRequestRecorder()
        let session = makeSession { request in
            let call = recorder.append(request)
            if call == 1 {
                #expect(request.url?.path == "/api/user/pay")
                return response(
                    for: request,
                    body: #"{"message":"success","data":{"pid":"1000","sign":"abc&123"},"url":"https://pay.example.com/submit"}"#
                )
            }
            #expect(request.url?.path == "/api/user/stripe/pay")
            return response(
                for: request,
                body: #"{"message":"success","data":{"pay_link":"https://checkout.stripe.com/c/pay"}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        let epay = try await client.createPaymentCheckout(.epay(amount: 20, paymentMethod: "alipay"))
        let stripe = try await client.createPaymentCheckout(.stripe(amount: 20))

        #expect(epay == .form(
            action: URL(string: "https://pay.example.com/submit")!,
            fields: ["pid": "1000", "sign": "abc&123"]
        ))
        #expect(stripe == .url(URL(string: "https://checkout.stripe.com/c/pay")!))
    }

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(
        for request: URLRequest,
        body: String,
        status: Int = 200,
        headers: [String: String] = [:]
    ) -> (HTTPURLResponse, Data) {
        var fields = headers
        fields["Content-Type"] = "application/json"
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: fields
        )!
        return (http, Data(body.utf8))
    }
}

private func requestBody(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class TestRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    @discardableResult
    func append(_ request: URLRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage.append(request)
        return storage.count
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
