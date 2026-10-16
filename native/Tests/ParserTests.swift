import XCTest
@testable import SleepCore

final class ParserTests: XCTestCase {
    func parse(_ changes: (inout [String: Any]) -> Void = { _ in }) throws -> SleepReport {
        var root = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        var day = (root["days"] as! [[String: Any]])[0]
        changes(&day); root["days"] = [day]
        return try ReportParser.parse(JSONSerialization.data(withJSONObject: root), timezone: "America/Los_Angeles", now: testNow)
    }
    func testAllMetricsAndPercentages() throws {
        let r = try parse()
        XCTAssertEqual(r.totalSleepSeconds, 27000); XCTAssertEqual(r.score, 88)
        XCTAssertEqual(r.stages.deep.seconds, 5400); XCTAssertEqual(r.stages.deep.percent, 20)
        XCTAssertEqual(r.stages.rem.percent, 20); XCTAssertEqual(r.stages.light.percent, 60)
        XCTAssertEqual(r.hrvMs, 42); XCTAssertEqual(r.respiratoryRate, 14.2)
        XCTAssertEqual(r.awakeSeconds, 1800); XCTAssertEqual(r.snoringSeconds, 120)
        XCTAssertEqual(r.date, "2026-10-14"); XCTAssertTrue(r.timesArePresence)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(r), as: UTF8.self).contains("performance"))
    }
    func testMissingRawHRVNeverUsesScoreAsMilliseconds() throws {
        let r = try parse { $0.removeValue(forKey: "hrv"); $0.removeValue(forKey: "snoringDurationSeconds") }
        XCTAssertNil(r.hrvMs); XCTAssertEqual(r.hrvScore, 80); XCTAssertNil(r.snoringSeconds)
        XCTAssertTrue(r.missingMetrics.contains("HRV milliseconds"))
    }
    func testZeroAndMissingAreDistinctAndBooleansAreRejected() throws {
        let r = try parse { $0["snoringDurationSeconds"] = 0; $0["heartRate"] = true; $0["respiratoryRate"] = NSNull() }
        XCTAssertEqual(r.snoringSeconds, 0); XCTAssertNil(r.heartRateBpm); XCTAssertNil(r.respiratoryRate)
        XCTAssertEqual(Display.duration(nil), "—"); XCTAssertEqual(Display.duration(0), "0m")
    }
    func testUnreconciledStageUnitsAreUnavailable() throws {
        let r = try parse { $0["stages"] = [["stage":"deep", "duration":90], ["stage":"rem", "duration":90], ["stage":"light", "duration":270]] }
        XCTAssertNil(r.stages.deep.seconds); XCTAssertNil(r.stages.light.percent); XCTAssertNil(r.awakeSeconds)
    }
    func testLatestCompletedIgnoresOngoingFutureAndUnsortedRows() throws {
        let root = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        let day = (root["days"] as! [[String: Any]])[0]
        var ongoing = day; ongoing["presenceEnd"] = NSNull(); ongoing["score"] = 1
        var future = day; future["presenceEnd"] = "2026-10-15T13:30:00Z"; future["score"] = 2
        var old = day; old["presenceStart"] = "2026-10-13T05:30:00Z"; old["presenceEnd"] = "2026-10-13T13:30:00Z"; old["score"] = 3
        let payload = try JSONSerialization.data(withJSONObject: ["days": [future, ongoing, old, day]])
        let r = try ReportParser.parse(payload, timezone: "America/Los_Angeles", now: testNow)
        XCTAssertEqual(r.score, 88)
    }
    func testEmptyMalformedAndImpossibleReports() throws {
        for data in [Data("{}".utf8), Data("not json".utf8), Data("{\"days\":[]}".utf8)] {
            XCTAssertThrowsError(try ReportParser.parse(data, timezone: "America/Los_Angeles", now: testNow))
        }
        XCTAssertThrowsError(try parse { $0["sleepDurationSeconds"] = 90000 })
        XCTAssertThrowsError(try parse { $0["presenceEnd"] = "2026-10-14T04:00:00Z" })
    }
    func testHRVSeriesFiltersOutOfWindowAndDuplicates() throws {
        let r = try parse {
            $0.removeValue(forKey: "hrv")
            $0["sessions"] = [["timeseries": ["hrv": [["2026-10-14T07:00:00Z",40], ["2026-10-14T07:00:00Z",40], ["2026-10-14T08:00:00Z",60], ["2026-10-14T17:00:00Z",999]]]]]
        }
        XCTAssertEqual(r.hrvMs, 50)
    }
    func testExplicitSleepTimesMustBeWithinPresenceWindow() throws {
        let r = try parse { $0["sleepStart"] = "2026-10-14T05:45:00Z"; $0["sleepEnd"] = "2026-10-14T13:15:00Z" }
        XCTAssertFalse(r.timesArePresence); XCTAssertEqual(r.bedtime, "2026-10-14T05:45:00Z")
    }
    func testCapturedV3SchemaUsesAggregateDurationsAndAvailableRawMetrics() throws {
        let report = try parse {
            $0.removeValue(forKey: "sleepDurationSeconds")
            $0.removeValue(forKey: "stages")
            $0.removeValue(forKey: "hrv")
            $0.removeValue(forKey: "heartRate")
            $0.removeValue(forKey: "respiratoryRate")
            $0.removeValue(forKey: "snoringDurationSeconds")
            $0["incomplete"] = false
            $0["sleepDuration"] = 27000
            $0["deepDuration"] = 5400
            $0["remDuration"] = 5400
            $0["lightDuration"] = 16200
            $0["snoreDuration"] = 120
            $0["sleepQualityScore"] = [
                "hrv": ["current": 42, "score": 80, "available": true],
                "heartRate": ["current": 55, "available": true],
                "respiratoryRate": ["current": 14.2, "available": true]
            ]
        }
        XCTAssertEqual(report.totalSleepSeconds, 27000)
        XCTAssertEqual(report.stages.deep.percent, 20)
        XCTAssertEqual(report.stages.rem.seconds, 5400)
        XCTAssertEqual(report.stages.light.percent, 60)
        XCTAssertEqual(report.hrvMs, 42)
        XCTAssertEqual(report.heartRateBpm, 55)
        XCTAssertEqual(report.respiratoryRate, 14.2)
        XCTAssertEqual(report.snoringSeconds, 120)
    }
    func testUnavailableV3MetricsNeverUseScoreOrAverage() throws {
        let report = try parse {
            $0.removeValue(forKey: "hrv")
            $0.removeValue(forKey: "heartRate")
            $0["sleepQualityScore"] = [
                "hrv": ["current": 42, "average": 40, "score": 80, "available": false],
                "heartRate": ["average": 55, "score": 90, "available": true]
            ]
        }
        XCTAssertNil(report.hrvMs)
        XCTAssertNil(report.heartRateBpm)
    }
    func testIncompleteDayIsSkippedEvenWithAnEndedPresenceWindow() throws {
        let root = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        let day = (root["days"] as! [[String: Any]])[0]
        var incomplete = day
        incomplete["presenceEnd"] = "2026-10-14T13:45:00Z"
        incomplete["incomplete"] = true
        incomplete["score"] = 1
        let data = try JSONSerialization.data(withJSONObject: ["days": [incomplete, day]])
        let report = try ReportParser.parse(data, timezone: "America/Los_Angeles", now: testNow)
        XCTAssertEqual(report.score, 88)
    }
    func testV3StageDurationsMustReconcile() throws {
        let report = try parse {
            $0.removeValue(forKey: "stages")
            $0["deepDuration"] = 90
            $0["remDuration"] = 90
            $0["lightDuration"] = 270
        }
        XCTAssertNil(report.stages.deep.seconds)
    }
    func testV3AwakeSumsMatchingSessionSummariesAndExcludesOutOfBed() throws {
        let report = try parse {
            $0["stages"] = [["stage": "deep", "duration": 5400], ["stage": "rem", "duration": 5400], ["stage": "light", "duration": 16200]]
            $0["sessions"] = [
                ["stageSummary": ["sleepDuration": 18000, "awakeDuration": 600, "outDuration": 200, "totalDuration": 18800]],
                ["stageSummary": ["sleepDuration": 9000, "awakeDuration": 300, "outDuration": 100, "totalDuration": 9400]]
            ]
        }
        XCTAssertEqual(report.awakeSeconds, 900)
        XCTAssertFalse(report.missingMetrics.contains("Awake time"))
        XCTAssertEqual(report.stageChartTotalSeconds, 27900)
        XCTAssertEqual(try XCTUnwrap(report.stageChartPercent(report.awakeSeconds)), 900 / 27900 * 100, accuracy: 0.001)
        let percentages = [report.stages.deep.seconds, report.stages.rem.seconds, report.stages.light.seconds, report.awakeSeconds].compactMap(report.stageChartPercent)
        XCTAssertEqual(percentages.reduce(0, +), 100, accuracy: 0.001)
    }
    func testIncompleteOrMismatchedSessionAwakeIsUnavailable() throws {
        for summaries: [[String: Any]] in [
            [["sleepDuration": 27000, "outDuration": 0, "totalDuration": 28000]],
            [["sleepDuration": 12000, "awakeDuration": 600, "outDuration": 0, "totalDuration": 12600]],
            [["sleepDuration": 27000, "awakeDuration": 600, "outDuration": 0, "totalDuration": 27000]],
            [["sleepDuration": 27000, "awakeDuration": true, "outDuration": 0, "totalDuration": 27000]]
        ] {
            let report = try parse {
                $0.removeValue(forKey: "stages")
                $0["deepDuration"] = 5400; $0["remDuration"] = 5400; $0["lightDuration"] = 16200
                $0["sessions"] = summaries.map { ["stageSummary": $0] }
            }
            XCTAssertNil(report.awakeSeconds)
            XCTAssertNil(report.stageChartPercent(report.awakeSeconds))
        }
    }
    func testV3AwakeZeroIsValidAndExcessiveAwakeIsRejected() throws {
        for awake in [0, 10000] {
            let report = try parse {
                $0.removeValue(forKey: "stages")
                $0["deepDuration"] = 5400; $0["remDuration"] = 5400; $0["lightDuration"] = 16200
                $0["sessions"] = [["stageSummary": ["sleepDuration": 27000, "awakeDuration": awake, "outDuration": 0, "totalDuration": 27000 + awake]]]
            }
            XCTAssertEqual(report.awakeSeconds, awake == 0 ? 0 : nil)
        }
    }
}
