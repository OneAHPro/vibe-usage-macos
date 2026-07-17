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
                body: #"{"success":true,"message":"","data":{"id":7,"username":"xuande","display_name":"徐安","role":1,"status":1,"group":"pro","used_quota":750000,"request_count":321}}"#
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
                body: #"{"success":true,"message":"","data":{"buckets":[{"source":"mac","model":"gpt-5.6-sol","project":"pro","hostname":"api.anhepro.com","bucketStart":"2026-07-16T01:00:00Z","inputTokens":110,"outputTokens":30,"cacheCreationInputTokens":10,"cachedInputTokens":60,"reasoningOutputTokens":0,"totalTokens":210,"estimatedCost":1.5}],"sessions":[],"hasAnyData":true}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        let usage = try await client.fetchUsage(range: .days(7))

        #expect(usage.hasAnyData)
        #expect(usage.buckets.count == 1)
        #expect(usage.buckets[0].computedTotal == 210)
        #expect(usage.buckets[0].estimatedCost == 1.5)
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
    }

    @Test
    func currentUserUsesSavedUserHeader() async throws {
        let session = makeSession { request in
            #expect(request.url?.path == "/api/user/self")
            #expect(request.value(forHTTPHeaderField: "New-Api-User") == "7")
            return response(
                for: request,
                body: #"{"success":true,"message":"","data":{"id":7,"username":"xuande","display_name":"徐安","role":1,"status":1,"group":"pro","used_quota":750000,"request_count":321}}"#
            )
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        let user = try await client.fetchCurrentUser()

        #expect(user.username == "xuande")
        #expect(user.usedQuota == 750_000)
        #expect(user.requestCount == 321)
    }

    @Test
    func missingDesktopEndpointFallsBackToExistingNewSystemLogs() async throws {
        let session = makeSession { request in
            switch request.url?.path {
            case "/api/desktop/usage":
                return response(
                    for: request,
                    body: #"{"error":{"message":"Invalid URL"}}"#,
                    status: 404
                )
            case "/api/status":
                return response(
                    for: request,
                    body: #"{"success":true,"message":"","data":{"quota_per_unit":500000}}"#
                )
            case "/api/log/self":
                #expect(request.value(forHTTPHeaderField: "New-Api-User") == "7")
                #expect(request.url?.query?.contains("type=2") == true)
                #expect(request.url?.query?.contains("page_size=100") == true)
                return response(
                    for: request,
                    body: #"{"success":true,"message":"","data":{"page":1,"page_size":100,"total":2,"items":[{"id":1,"user_id":7,"created_at":1784178300,"type":2,"content":"","username":"xuande","token_name":"codex","model_name":"gpt-5.6-sol","quota":500000,"prompt_tokens":100,"completion_tokens":20,"use_time":2,"is_stream":true,"channel":1,"channel_name":"","token_id":1,"group":"pro","ip":"","other":"{\"cache_tokens\":40}"},{"id":2,"user_id":7,"created_at":1784180100,"type":2,"content":"","username":"xuande","token_name":"codex","model_name":"gpt-5.6-sol","quota":250000,"prompt_tokens":80,"completion_tokens":10,"use_time":3,"is_stream":true,"channel":1,"channel_name":"","token_id":1,"group":"pro","ip":"","other":"{\"cache_tokens\":20,\"cache_write_tokens\":10}"}]}}"#
                )
            default:
                Issue.record("Unexpected fallback request: \(request.url?.absoluteString ?? "nil")")
                return response(for: request, body: "{}", status: 500)
            }
        }
        let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

        let usage = try await client.fetchUsage(range: .days(1))

        #expect(usage.hasAnyData)
        #expect(usage.buckets.count == 1)
        #expect(usage.buckets[0].inputTokens == 110)
        #expect(usage.buckets[0].cachedInputTokens == 60)
        #expect(usage.buckets[0].cacheCreationInputTokens == 10)
        #expect(usage.buckets[0].totalTokens == 210)
        #expect(usage.buckets[0].estimatedCost == 1.5)
        #expect(usage.sessions?.first?.messageCount == 2)
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

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(for request: URLRequest, body: String, status: Int = 200) -> (HTTPURLResponse, Data) {
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
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
