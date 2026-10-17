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
    func testPhaseQualifiedStatusDecodesAsActiveBed() async throws {
        let transport = MockTransport([response("{\"currentLevel\":-13,\"currentState\":{\"type\":\"smart:bedtime\"}}")])
        let status = try await client(transport).podStatus(credentials: credentials(), cachedToken: cached) { _ in }
        XCTAssertTrue(status.isOn)
        XCTAssertFalse(status.isOff)
        XCTAssertEqual(status.currentState.type, "smart:bedtime")
        XCTAssertEqual(PodControlState(status: status, checkedAt: testNow, activity: .idle, now: testNow), .on)
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
    func testPowerCommandsSetPowerForCurrentUser() async throws {
        for (action, state) in [(PodAction.turnOn, "smart"), (.turnOff, "off")] {
            let transport = MockTransport([response("", status: 204)])
            try await client(transport).control(action, credentials: credentials(), cachedToken: cached) { _ in }
            let requests = await transport.recorded()
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests[0].url?.path, "/v1/users/uid/temperature")
            let body = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: [String: String]]
            XCTAssertEqual(body, ["currentState": ["type": state]])
        }
    }
    func testEndSleepPowersOffThenStopsNewestRecentIncompleteInterval() async throws {
        let transport = MockTransport([
            response("", status: 204),
            response("""
            {"intervals":[
              {"id":"complete","ts":"2026-10-14T13:59:00Z"},
              {"id":"older","ts":"2026-10-14T05:00:00Z","incomplete":true},
              {"id":"active","ts":"2026-10-14T06:00:00.000Z","incomplete":true}
            ]}
            """), response("", status: 204)])
        try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://app-api.8slp.net/v1/users/uid/temperature")
        XCTAssertEqual(requests[0].httpMethod, "PUT")
        let power = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: [String: String]]
        XCTAssertEqual(power, ["currentState": ["type": "off"]])
        XCTAssertEqual(requests[1].url?.absoluteString, "https://client-api.8slp.net/v1/users/uid/intervals")
        XCTAssertEqual(requests[2].url?.path, "/v1/users/uid/intervals/active")
        XCTAssertEqual(requests[2].httpMethod, "PUT")
        let body = try JSONSerialization.jsonObject(with: requests[2].httpBody!) as! [String: String]
        XCTAssertEqual(body, ["edit": "stop"])
    }
    func testEndSleepDoesNotEditCompletedStaleOrFutureIntervals() async throws {
        for item in [
            "{\"id\":\"done\",\"ts\":\"2026-10-14T06:00:00Z\"}",
            "{\"id\":\"old\",\"ts\":\"2026-10-10T06:00:00Z\",\"incomplete\":true}",
            "{\"id\":\"future\",\"ts\":\"2026-10-15T06:00:00Z\",\"incomplete\":true}"
        ] {
            let transport = MockTransport([response("", status: 204), response("{\"intervals\":[\(item)]}")])
            try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }
            let requests = await transport.recorded(); XCTAssertEqual(requests.count, 2)
            XCTAssertEqual(requests.last?.httpMethod, "GET")
        }
    }
    func testEndSleepWriteIsNotReplayedOnServerFailure() async throws {
        let transport = MockTransport([response("", status: 204), response("{\"intervals\":[{\"id\":\"active\",\"ts\":\"2026-10-14T06:00:00Z\",\"incomplete\":true}]}"), response("", status: 503)])
        do { try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? SleepError, .bedOffSleepUnconfirmed) }
        let count = await transport.recorded().count; XCTAssertEqual(count, 3)
    }
    func testEndSleepBypassesFreshReportCacheAndReadsConsistently() async throws {
        let secure = MemorySession(); secure.saved = SavedSession(credentials: try credentials(), token: cached)
        let transport = MockTransport([
            HTTPResult(data: try fixture(), status: 200),
            response("", status: 204),
            response("{\"intervals\":[{\"id\":\"active\",\"ts\":\"2026-10-14T06:00:00Z\",\"incomplete\":true}]}"),
            response("", status: 204), HTTPResult(data: try fixture(), status: 200)])
        let service = SleepService(secure: secure, cache: MemoryReports(), client: client(transport), now: { testNow })
        _ = try await service.latest()
        try await service.control(.endSleep)
        _ = try await service.latest()
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 5)
        let query = URLComponents(url: requests[4].url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "consistent-read" }?.value, "true")
    }
    func testEndSleepDoesNotContinueAfterUnconfirmedPowerOff() async throws {
        for status in [429, 503] {
            let transport = MockTransport([response("", status: status)])
            do { try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
            catch { XCTAssertEqual(error as? SleepError, status == 429 ? .rateLimited : .controlUnconfirmed) }
            let count = await transport.recorded().count; XCTAssertEqual(count, 1)
        }
    }
    func testEndSleepReportsBedOffWhenIntervalLookupFails() async throws {
        let transport = MockTransport([response("", status: 204), response("{}")])
        do { try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? SleepError, .bedOffSleepUnconfirmed) }
        let count = await transport.recorded().count; XCTAssertEqual(count, 2)
    }
    func testEndSleepWhenNoActiveSessionStillPowersOff() async throws {
        let transport = MockTransport([response("", status: 204), response("{\"intervals\":[]}")])
        try await client(transport).control(.endSleep, credentials: credentials(), cachedToken: cached) { _ in }
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.httpMethod, "PUT")
        XCTAssertEqual(requests.last?.httpMethod, "GET")
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

final class PodControlStateTests: XCTestCase {
    private let off = PodStatus(currentLevel: -20, currentState: .init(type: "off"))
    private let on = PodStatus(currentLevel: -20, currentState: .init(type: "smart"))
    private let actions: [PodAction] = [.turnOn, .temperature(-40), .endSleep, .turnOff]

    private func state(_ status: PodStatus?, age: TimeInterval = 0,
                       activity: PodControlActivity = .idle) -> PodControlState {
        PodControlState(status: status, checkedAt: testNow.addingTimeInterval(-age), activity: activity, now: testNow)
    }
    func testOffOffersNoCommands() {
        let value = state(off)
        XCTAssertEqual(value, .off)
        XCTAssertTrue(actions.filter(value.allows).isEmpty)
    }
    func testOnAllowsTemperatureAndEndSleepButNotTurnOnOrSeparateOff() {
        let value = state(on)
        XCTAssertEqual(value, .on)
        XCTAssertEqual(actions.filter(value.allows), [.temperature(-40), .endSleep])
    }
    func testExpiredOrMissingStatusNeverAllowsCommands() {
        for value in [state(on, age: 60), state(off, age: 61), state(nil),
                      PodControlState(status: on, checkedAt: nil, activity: .idle, now: testNow)] {
            XCTAssertTrue(actions.filter(value.allows).isEmpty)
        }
        XCTAssertEqual(state(on, age: 59.9), .on)
        XCTAssertEqual(state(off, age: 60), .refreshRequired)
        XCTAssertEqual(state(nil), .unavailable)
    }
    func testInFlightAndUnconfirmedCommandsHideOldStateActions() {
        for status in [on, off] {
            for activity in [PodControlActivity.refreshing, .sending(.endSleep), .confirming(.turnOn)] {
                XCTAssertTrue(actions.filter(state(status, activity: activity).allows).isEmpty)
            }
        }
        XCTAssertEqual(state(off, activity: .refreshing), .loading)
        XCTAssertEqual(state(on, activity: .sending(.endSleep)), .changing(.endSleep))
        XCTAssertEqual(state(off, activity: .confirming(.turnOn)), .confirming(.turnOn))
    }
    func testUnknownModesNeverImplyOnOrAllowControls() {
        let value = state(PodStatus(currentLevel: 0, currentState: .init(type: "future-mode")))
        XCTAssertEqual(value, .unsupported("future-mode"))
        XCTAssertTrue(actions.filter(value.allows).isEmpty)
    }
    func testSmartPhaseModesAllowActiveControlsAndConfirmSetpoint() {
        // bedtime is observed live; other suffixes exercise the smart: family rule.
        for mode in ["smart:bedtime", "smart:initialsleep", "smart:finalsleep", "smart:future-phase"] {
            let phased = PodStatus(currentLevel: -20, currentState: .init(type: mode))
            let value = state(phased)
            XCTAssertTrue(phased.isOn)
            XCTAssertEqual(value, .on)
            XCTAssertEqual(actions.filter(value.allows), [.temperature(-40), .endSleep])
            XCTAssertTrue(PodAction.turnOn.isConfirmed(by: phased))
            XCTAssertTrue(PodAction.temperature(-20).isConfirmed(by: phased))
            XCTAssertFalse(PodAction.temperature(-40).isConfirmed(by: phased))
            XCTAssertFalse(PodAction.endSleep.isConfirmed(by: phased))
        }
        for mode in ["smart:", "smarter", "off:future", "unknown"] {
            let value = state(PodStatus(currentLevel: 0, currentState: .init(type: mode)))
            XCTAssertEqual(value, .unsupported(mode))
            XCTAssertTrue(actions.filter(value.allows).isEmpty)
        }
    }
    func testReadbackMustMatchCommandBeforeRestoringActions() {
        XCTAssertTrue(PodAction.turnOn.isConfirmed(by: on))
        XCTAssertFalse(PodAction.turnOn.isConfirmed(by: off))
        XCTAssertTrue(PodAction.endSleep.isConfirmed(by: off))
        XCTAssertFalse(PodAction.endSleep.isConfirmed(by: on))
        XCTAssertTrue(PodAction.temperature(-20).isConfirmed(by: on))
        XCTAssertFalse(PodAction.temperature(-40).isConfirmed(by: on))
        XCTAssertFalse(PodAction.temperature(-20).isConfirmed(by: off))
    }
}
