import XCTest
@testable import SleepCore

final class ServiceTests: XCTestCase {
    func make(_ replies: [HTTPResult], cached: ReportEnvelope? = nil, delay: Duration = .zero) throws -> (SleepService, MemorySession, MemoryReports, MockTransport) {
        let secure = MemorySession(), cache = MemoryReports(), transport = MockTransport(replies, delay: delay)
        secure.saved = SavedSession(credentials: try credentials(), token: nil); cache.value = cached
        let client = EightClient(transport: transport, now: { testNow }, wait: { _ in })
        return (SleepService(secure: secure, cache: cache, client: client, now: { testNow }), secure, cache, transport)
    }
    func testFreshCacheSkipsNetworkButManualRefreshFetches() async throws {
        let cached = try JSONDecoder().decode(ReportEnvelope.self, from: fixture("report"))
        let (service, _, _, transport) = try make([loginResponse, HTTPResult(data: fixture(), status: 200)], cached: cached)
        let first = try await service.latest(); XCTAssertEqual(first, cached)
        var count = await transport.recorded().count; XCTAssertEqual(count, 0)
        _ = try await service.latest(force: true)
        count = await transport.recorded().count; XCTAssertEqual(count, 2)
    }
    func testOfflineFallbackAndCooldownAreExplicit() async throws {
        let cached = try JSONDecoder().decode(ReportEnvelope.self, from: fixture("report"))
        let (service, _, _, transport) = try make([response("private credentials", status: 400)], cached: cached)
        let result = try await service.latest(force: true)
        XCTAssertTrue(result.stale); XCTAssertEqual(result.fetchedAt, cached.fetchedAt)
        XCTAssertTrue(result.warning!.contains("saved")); XCTAssertFalse(result.warning!.contains("private credentials"))
        _ = try await service.latest(force: true)
        let automatic = try await service.latest()
        XCTAssertTrue(automatic.stale)
        let count = await transport.recorded().count; XCTAssertEqual(count, 1)
        XCTAssertTrue(SleepSummary.text(result, now: testNow).contains("older or cached"))
    }
    func testMissingConfigurationAndNoReportErrors() async throws {
        let (service, secure, _, _) = try make([loginResponse, response("{\"days\":[]}")])
        do { _ = try await service.latest(); XCTFail() } catch { XCTAssertEqual(error as? SleepError, .noCompletedReport) }
        try await service.signOut()
        XCTAssertNil(secure.saved)
        do { _ = try await service.latest(); XCTFail() } catch { XCTAssertEqual(error as? SleepError, .notConfigured) }
    }
    func testConcurrentRequestsCoalesce() async throws {
        let (service, _, _, transport) = try make([loginResponse, HTTPResult(data: fixture(), status: 200)], delay: .milliseconds(30))
        async let first = service.latest(force: true)
        async let second = service.latest(force: true)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a, b)
        let count = await transport.recorded().count; XCTAssertEqual(count, 2)
    }
    func testAccountSwitchCancelsOldFetchAndClearsData() async throws {
        let cached = try JSONDecoder().decode(ReportEnvelope.self, from: fixture("report"))
        let (service, secure, cache, transport) = try make([loginResponse, HTTPResult(data: fixture(), status: 200)], cached: cached, delay: .milliseconds(100))
        let fetch = Task { try await service.latest(force: true) }
        while await transport.recorded().isEmpty { await Task.yield() }
        try await service.configure(credentials("other@example.com"))
        do { _ = try await fetch.value; XCTFail("Old fetch must be cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(cache.value); XCTAssertNil(secure.saved?.token)
        XCTAssertEqual(secure.saved?.credentials.email, "other@example.com")
    }
    func testCacheRoundTripAndCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileReportStorage(url: directory.appendingPathComponent("report.json"))
        XCTAssertNil(try cache.read())
        let report = try JSONDecoder().decode(ReportEnvelope.self, from: fixture("report"))
        try cache.write(report); XCTAssertEqual(try cache.read(), report)
        try Data("bad".utf8).write(to: cache.url); XCTAssertThrowsError(try cache.read())
        try cache.clear(); XCTAssertNil(try cache.read())
    }
    func testSummaryFormattingAndStaleThreshold() throws {
        let report = try JSONDecoder().decode(ReportEnvelope.self, from: fixture("report"))
        let text = SleepSummary.text(report, now: testNow)
        XCTAssertTrue(text.contains("7 hours 30 minutes")); XCTAssertTrue(text.contains("88"))
        XCTAssertFalse(text.contains("older or cached"))
        XCTAssertTrue(report.isStale(now: testNow.addingTimeInterval(901)))
        XCTAssertEqual(SleepSummary.duration(3599), "1 hour")
    }
}

extension ServiceTests {
    func testFailureWarningClearsOnlyAfterSuccessfulFetchFollowingCooldown() async throws {
        final class Clock { var value = testNow }
        let clock = Clock(), secure = MemorySession(), cache = MemoryReports()
        secure.saved = SavedSession(credentials: try credentials(), token: nil)
        cache.value = try JSONDecoder().decode(ReportEnvelope.self, from: fixture("report"))
        let transport = MockTransport([response("", status: 400), loginResponse, HTTPResult(data: try fixture(), status: 200)])
        let service = SleepService(secure: secure, cache: cache,
            client: EightClient(transport: transport, now: { clock.value }), now: { clock.value })
        let failed = try await service.latest(force: true)
        XCTAssertTrue(failed.stale)
        clock.value = clock.value.addingTimeInterval(61)
        let recovered = try await service.latest()
        XCTAssertFalse(recovered.stale); XCTAssertNil(recovered.warning)
        let count = await transport.recorded().count; XCTAssertEqual(count, 3)
    }
}
