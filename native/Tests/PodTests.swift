import XCTest
@testable import SleepCore

final class PodTests: XCTestCase {
    private let cached = AccessToken(value: "cached", expiresAt: testNow.addingTimeInterval(1000), userID: "uid")
    private func client(_ transport: MockTransport) -> EightClient {
        EightClient(transport: transport, now: { testNow }, wait: { _ in })
    }
    func testStatusUsesAppHostAndCurrentUser() async throws {
        let transport = MockTransport([response("{\"currentLevel\":-20,\"currentState\":{\"type\":\"smart\"}}")])
        let status = try await client(transport).podStatus(credentials: credentials(), cachedToken: cached) { _ in }
        XCTAssertEqual(status.currentLevel, -20); XCTAssertFalse(status.isOff)
        let requests = await transport.recorded()
        XCTAssertEqual(requests[0].url?.absoluteString, "https://app-api.8slp.net/v1/users/uid/temperature")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer cached")
    }
    func testTemperatureEnablesSmartThenWritesLevelAndAcceptsEmpty204() async throws {
        let transport = MockTransport([response("", status: 204), response("", status: 204)])
        try await client(transport).control(.temperature(-40), credentials: credentials(), cachedToken: cached) { _ in }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "PUT" && $0.url?.host == "app-api.8slp.net" })
        let first = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: [String: String]]
        let second = try JSONSerialization.jsonObject(with: requests[1].httpBody!) as! [String: Int]
        XCTAssertEqual(first, ["currentState": ["type": "smart"]])
        XCTAssertEqual(second, ["currentLevel": -40])
    }
    func testTurnOnSetsPowerForCurrentUser() async throws {
        for (action, state) in [(PodAction.turnOn, "smart")] {
            let transport = MockTransport([response("", status: 204)])
            try await client(transport).control(action, credentials: credentials(), cachedToken: cached) { _ in }
            let requests = await transport.recorded()
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests[0].url?.path, "/v1/users/uid/temperature")
            let body = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: [String: String]]
            XCTAssertEqual(body, ["currentState": ["type": state]])
        }
    }
    func testEndSleepStopsNewestRecentIncompleteInterval() async throws {
        let transport = MockTransport([
            response("""
            {"intervals":[
              {"id":"complete","ts":"2026-10-14T13:59:00Z"},
              {"id":"older","ts":"2026-10-14T05:00:00Z","incomplete":true},
              {"id":"active","ts":"2026-10-14T06:00:00.000Z","incomplete":true}
            ]}
            """), response("", status: 204)])
        try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://client-api.8slp.net/v1/users/uid/intervals")
        XCTAssertEqual(requests[1].url?.path, "/v1/users/uid/intervals/active")
        XCTAssertEqual(requests[1].httpMethod, "PUT")
        let body = try JSONSerialization.jsonObject(with: requests[1].httpBody!) as! [String: String]
        XCTAssertEqual(body, ["edit": "stop"])
    }
    func testEndSleepDoesNotEditCompletedStaleOrFutureIntervals() async throws {
        for item in [
            "{\"id\":\"done\",\"ts\":\"2026-10-14T06:00:00Z\"}",
            "{\"id\":\"old\",\"ts\":\"2026-10-10T06:00:00Z\",\"incomplete\":true}",
            "{\"id\":\"future\",\"ts\":\"2026-10-15T06:00:00Z\",\"incomplete\":true}"
        ] {
            let transport = MockTransport([response("{\"intervals\":[\(item)]}")])
            do { try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
            catch { XCTAssertEqual(error as? SleepError, .noActiveSleep) }
            let count = await transport.recorded().count; XCTAssertEqual(count, 1)
        }
    }
    func testEndSleepWriteIsNotReplayedOnServerFailure() async throws {
        let transport = MockTransport([response("{\"intervals\":[{\"id\":\"active\",\"ts\":\"2026-10-14T06:00:00Z\",\"incomplete\":true}]}"), response("", status: 503)])
        do { try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? SleepError, .controlUnconfirmed) }
        let count = await transport.recorded().count; XCTAssertEqual(count, 2)
    }
    func testEndSleepBypassesFreshReportCacheAndReadsConsistently() async throws {
        let secure = MemorySession(); secure.saved = SavedSession(credentials: try credentials(), token: cached)
        let transport = MockTransport([
            HTTPResult(data: try fixture(), status: 200),
            response("{\"intervals\":[{\"id\":\"active\",\"ts\":\"2026-10-14T06:00:00Z\",\"incomplete\":true}]}"),
            response("", status: 204), HTTPResult(data: try fixture(), status: 200)])
        let service = SleepService(secure: secure, cache: MemoryReports(), client: client(transport), now: { testNow })
        _ = try await service.latest()
        try await service.control(.endSleep)
        _ = try await service.latest()
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 4)
        let query = URLComponents(url: requests[3].url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "consistent-read" }?.value, "true")
    }
    func testInvalidLevelDoesNotAuthenticateOrSendAnyRequest() async throws {
        let transport = MockTransport([])
        for level in [-101, 101] {
            do { try await client(transport).control(.temperature(level), credentials: credentials(), cachedToken: nil) { _ in }; XCTFail() }
            catch { XCTAssertEqual(error as? SleepError, .invalidTemperature) }
        }
        let requests = await transport.recorded(); XCTAssertTrue(requests.isEmpty)
    }
    func testWrite401RenewsAndReplaysTheSameBody() async throws {
        let transport = MockTransport([response("", status: 401), loginResponse, response("", status: 204)])
        let tokens = TokenRecorder()
        try await client(transport).control(.turnOn, credentials: credentials(), cachedToken: cached) { await tokens.add($0) }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 3); XCTAssertEqual(requests[0].httpBody, requests[2].httpBody)
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        let saved = await tokens.all(); XCTAssertNil(saved[0]); XCTAssertEqual(saved[1]?.value, "new-token")
    }
    func testWritesDoNotRetryTransientOrAmbiguousFailures() async throws {
        for reply in [response("", status: 503), response("", status: 429)] {
            let transport = MockTransport([reply, response("", status: 204)])
            do { try await client(transport).control(.turnOn, credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
            catch { XCTAssertEqual(error as? SleepError, reply.status == 429 ? .rateLimited : .controlUnconfirmed) }
            let count = await transport.recorded().count; XCTAssertEqual(count, 1)
        }
        let transport = MockTransport([])
        do { try await client(transport).control(.turnOn, credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? SleepError, .controlUnconfirmed) }
        let count = await transport.recorded().count; XCTAssertEqual(count, 1)
    }
    func testPartialTemperatureFailureIsExplicitAndNotReplayed() async throws {
        let transport = MockTransport([response("", status: 204), response("private response", status: 500), response("", status: 204)])
        do { try await client(transport).control(.temperature(20), credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? SleepError, .partialTemperatureChange) }
        let count = await transport.recorded().count; XCTAssertEqual(count, 2)
    }
    func testMalformedStatusIsRejected() async throws {
        for data in ["{}", "{\"currentLevel\":101,\"currentState\":{\"type\":\"smart\"}}", "{\"currentLevel\":0,\"currentState\":{\"type\":\"\"}}"] {
            let transport = MockTransport([response(data)])
            do { _ = try await client(transport).podStatus(credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
            catch { XCTAssertEqual(error as? SleepError, .invalidResponse) }
        }
    }
    func testControlsDiscoverUserIDWithoutHouseholdSideWrites() async throws {
        let transport = MockTransport([loginResponse, response("", status: 204)])
        try await client(transport).control(.turnOn, credentials: credentials(), cachedToken: nil) { _ in }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 2); XCTAssertEqual(requests[1].url?.path, "/v1/users/uid/temperature")
    }
    func testServiceReusesTokenAndDoesNotNeedCompletedReport() async throws {
        let secure = MemorySession(), cache = MemoryReports()
        secure.saved = SavedSession(credentials: try credentials(), token: cached)
        let transport = MockTransport([response("{\"currentLevel\":0,\"currentState\":{\"type\":\"off\"}}"), response("", status: 204)])
        let service = SleepService(secure: secure, cache: cache, client: client(transport), now: { testNow })
        let status = try await service.podStatus(); XCTAssertTrue(status.isOff)
        try await service.control(.turnOn)
        XCTAssertNil(cache.value)
        let count = await transport.recorded().count; XCTAssertEqual(count, 2)
    }
    func testServiceRejectsOverlappingCommandsAndSignOutCancelsOldCommand() async throws {
        let secure = MemorySession(); secure.saved = SavedSession(credentials: try credentials(), token: cached)
        let transport = MockTransport([response("", status: 204)], delay: .milliseconds(200))
        let service = SleepService(secure: secure, cache: MemoryReports(), client: client(transport), now: { testNow })
        let first = Task { try await service.control(.turnOn) }
        while await transport.recorded().isEmpty { await Task.yield() }
        do { try await service.control(.turnOn); XCTFail() }
        catch { XCTAssertEqual(error as? SleepError, .controlsBusy) }
        try await service.signOut()
        do { try await first.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(secure.saved)
    }
    func testReportAndControlShareOneTokenRenewal() async throws {
        let secure = MemorySession(); secure.saved = SavedSession(credentials: try credentials(), token: nil)
        let transport = MockTransport([loginResponse, HTTPResult(data: try fixture(), status: 200), response("", status: 204)], delay: .milliseconds(30))
        let service = SleepService(secure: secure, cache: MemoryReports(), client: client(transport), now: { testNow })
        let report = Task { try await service.latest(force: true) }
        while await transport.recorded().isEmpty { await Task.yield() }
        try await service.control(.turnOn)
        _ = try await report.value
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
}
