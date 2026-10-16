import XCTest
@testable import SleepCore

final class SleepScoreTests: XCTestCase {
    func testSnapshotFormatsAndAgesWithoutAnotherFetch() throws {
        let envelope = try JSONDecoder().decode(ReportEnvelope.self, from: fixture("report"))
        let score = try XCTUnwrap(SleepScoreSnapshot(envelope))
        XCTAssertEqual(score.scoreText, "88")
        XCTAssertFalse(score.isStale(at: testNow))
        XCTAssertTrue(score.isStale(at: testNow.addingTimeInterval(901)))
        let offline = SleepScoreSnapshot(ReportEnvelope(report: envelope.report, fetchedAt: envelope.fetchedAt, stale: true, warning: nil))!
        XCTAssertTrue(offline.isStale(at: testNow))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("report")) as? [String: Any])
        var report = try XCTUnwrap(json["report"] as? [String: Any])
        report["score"] = NSNull(); json["report"] = report
        let missing = try JSONDecoder().decode(ReportEnvelope.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(SleepScoreSnapshot(missing)?.scoreText, "—")
    }
    func testServicePublishesCachedAndOfflineScoresAndClearsOnAccountChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = SleepScoreSnapshotStorage(url: directory.appendingPathComponent("score.json"))
        let secure = MemorySession(), cache = MemoryReports()
        secure.saved = SavedSession(credentials: try credentials(), token: nil)
        cache.value = try JSONDecoder().decode(ReportEnvelope.self, from: fixture("report"))
        let transport = MockTransport([response("", status: 400), loginResponse, HTTPResult(data: try fixture(), status: 200)])
        let service = SleepService(secure: secure, cache: cache, client: EightClient(transport: transport, now: { testNow }), scoreStorage: storage, now: { testNow })
        _ = try await service.cached()
        XCTAssertEqual(storage.read()?.scoreText, "88")
        _ = try await service.latest(force: true)
        XCTAssertEqual(storage.read()?.stale, true)
        try await service.configure(credentials("other@example.com"))
        XCTAssertNil(storage.read())
        _ = try await service.latest(force: true)
        XCTAssertNotNil(storage.read())
        XCTAssertEqual(storage.read()?.stale, false)
        try await service.signOut()
        XCTAssertNil(storage.read())
        try Data("bad".utf8).write(to: storage.url!)
        XCTAssertNil(storage.read())
    }
}
