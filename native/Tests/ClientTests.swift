import XCTest
@testable import SleepCore

final class ClientTests: XCTestCase {
    func testLoginFormHeadersQueryAndExpiry() async throws {
        let transport = MockTransport([loginResponse, HTTPResult(data: try fixture(), status: 200)])
        let recorder = TokenRecorder()
        let client = EightClient(transport: transport, now: { testNow }, wait: { _ in })
        _ = try await client.fetch(credentials: credentials(), cachedToken: nil) { await recorder.add($0) }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://auth-api.8slp.net/v1/tokens")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let form = String(decoding: requests[0].httpBody!, as: UTF8.self)
        XCTAssertTrue(form.contains("password=password%20%2B%26%3D%C3%BC"))
        XCTAssertTrue(form.contains("grant_type=password")); XCTAssertTrue(form.contains(EightClient.clientID))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        let parts = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(query["from"], "2026-09-30"); XCTAssertEqual(query["to"], "2026-10-14")
        XCTAssertEqual(query["tz"], "America/Los_Angeles"); XCTAssertEqual(query["include-all-sessions"], "true")
        XCTAssertEqual(query["include-main"], "false"); XCTAssertEqual(query["model-version"], "v3")
        let tokens = await recorder.all()
        XCTAssertEqual(tokens[0]?.expiresAt, testNow.addingTimeInterval(3540))
    }
    func testUserIDDiscoveryAndCachedTokenAvoidLogin() async throws {
        let transport = MockTransport([response("{\"user\":{\"userId\":\"uid\"}}"), HTTPResult(data: try fixture(), status: 200)])
        let token = AccessToken(value: "cached", expiresAt: testNow.addingTimeInterval(1000))
        _ = try await EightClient(transport: transport, now: { testNow }).fetch(credentials: credentials(), cachedToken: token) { _ in }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2); XCTAssertEqual(requests[0].url?.path, "/v1/users/me")
        XCTAssertEqual(requests[1].url?.path, "/v1/users/uid/trends")
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func test401InvalidatesThenRenewsOnce() async throws {
        let transport = MockTransport([response("private body", status: 401), loginResponse, HTTPResult(data: try fixture(), status: 200)])
        let recorder = TokenRecorder()
        let cached = AccessToken(value: "rejected", expiresAt: testNow.addingTimeInterval(1000), userID: "uid")
        _ = try await EightClient(transport: transport, now: { testNow }).fetch(credentials: credentials(), cachedToken: cached) { await recorder.add($0) }
        let tokens = await recorder.all(); XCTAssertNil(tokens[0]); XCTAssertEqual(tokens[1]?.value, "new-token")
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 3); XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
    }
    func testRepeated401FailsWithoutLoginLoopOrLeakingBody() async throws {
        let transport = MockTransport([loginResponse, response("secret", status: 401), loginResponse, response("secret", status: 401)])
        do { _ = try await EightClient(transport: transport, now: { testNow }).fetch(credentials: credentials(), cachedToken: nil) { _ in }; XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? SleepError, .authentication); XCTAssertFalse(error.localizedDescription.contains("secret")) }
        let count = await transport.recorded().count; XCTAssertEqual(count, 4)
    }
    func test429AndServerFailuresAreBounded() async throws {
        let transport = MockTransport([loginResponse, response("", status: 429), response("", status: 503), response("", status: 429)])
        do { _ = try await EightClient(transport: transport, now: { testNow }, wait: { _ in }).fetch(credentials: credentials(), cachedToken: nil) { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? SleepError, .rateLimited) }
        let count = await transport.recorded().count; XCTAssertEqual(count, 4)
    }
    func testLongRetryAfterDoesNotRetryEarly() async throws {
        let transport = MockTransport([loginResponse, response("", status: 429, retry: "120")])
        do { _ = try await EightClient(transport: transport, now: { testNow }, wait: { _ in XCTFail("Should not wait") }).fetch(credentials: credentials(), cachedToken: nil) { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? SleepError, .rateLimited) }
        XCTAssertEqual(EightClient.retryDelay("Wed, 14 Oct 2026 14:02:00 GMT", now: testNow, fallback: 1), 120)
    }
    func testExpiredTokenRenewsAndMissingExpiryDefaults() async throws {
        let transport = MockTransport([response("{\"access_token\":\"token\",\"userId\":\"uid\"}"), HTTPResult(data: try fixture(), status: 200)])
        let recorder = TokenRecorder()
        _ = try await EightClient(transport: transport, now: { testNow }).fetch(credentials: credentials(), cachedToken: AccessToken(value: "old", expiresAt: testNow.addingTimeInterval(-1))) { await recorder.add($0) }
        let tokens = await recorder.all(); XCTAssertEqual(tokens[0]?.expiresAt, testNow.addingTimeInterval(3540))
    }
    func testBadLoginDoesNotRetry() async throws {
        for reply in [response("credentials", status: 400), response("{}"), response("{\"access_token\":\"\"}")] {
            let transport = MockTransport([reply])
            do { _ = try await EightClient(transport: transport, now: { testNow }).fetch(credentials: credentials(), cachedToken: nil) { _ in }; XCTFail() } catch { }
            let count = await transport.recorded().count; XCTAssertEqual(count, 1)
        }
    }
}

extension ClientTests {
    func testDateRangeUsesLocalCalendarAcrossDSTAndUTCMidnight() async throws {
        let clock = ISO8601DateFormatter().date(from: "2026-11-02T07:30:00Z")!
        let transport = MockTransport([loginResponse, HTTPResult(data: try fixture(), status: 200)])
        _ = try await EightClient(transport: transport, now: { clock }).fetch(credentials: credentials(), cachedToken: nil) { _ in }
        let requests = await transport.recorded()
        let items = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        XCTAssertEqual(query["to"], "2026-11-01")
        XCTAssertEqual(query["from"], "2026-10-18")
    }
}
