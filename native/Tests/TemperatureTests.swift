import XCTest
@testable import SleepCore

final class TemperatureTests: XCTestCase {
    func testRepresentativeSetpointsUseNonlinearMapping() throws {
        for (fahrenheit, level) in [(55,-100), (68,-58), (72,-40), (77,-18), (80,-3), (81,1), (86,16), (100,60), (107,80), (110,92)] {
            XCTAssertEqual(try PodTemperature.level(fahrenheit: Double(fahrenheit)), level)
            XCTAssertEqual(PodTemperature.fahrenheit(level: level), fahrenheit)
        }
    }
    func testEverySelectableFahrenheitDegreeRoundTrips() throws {
        for fahrenheit in 55...110 {
            let level = try PodTemperature.level(fahrenheit: Double(fahrenheit))
            XCTAssertEqual(PodTemperature.fahrenheit(level: level), fahrenheit)
        }
    }
    func testLevelReadbackIsMonotonicAndUsesNearestEntry() {
        let degrees = (-100...100).compactMap { PodTemperature.fahrenheit(level: $0) }
        XCTAssertEqual(degrees.count, 201)
        XCTAssertEqual(degrees, degrees.sorted())
        XCTAssertEqual(PodTemperature.fahrenheit(level: -20), 76)
        XCTAssertEqual(PodTemperature.fahrenheit(level: 0), 81)
        // Preserve an existing out-of-selector-range readback rather than relabeling it.
        XCTAssertEqual(PodTemperature.fahrenheit(level: 100), 111)
        XCTAssertNil(PodTemperature.fahrenheit(level: -101))
        XCTAssertNil(PodTemperature.fahrenheit(level: 101))
    }
    func testInvalidFahrenheitIsRejectedRatherThanClampedOrTruncated() {
        for value in [54,111,68.5,Double.nan,Double.infinity,-Double.infinity] {
            XCTAssertThrowsError(try PodTemperature.level(fahrenheit: value)) {
                XCTAssertEqual($0 as? SleepError, .invalidFahrenheit)
            }
        }
    }
    func testFahrenheitSelectionSendsConvertedLevelNotDegrees() async throws {
        let transport = MockTransport([response("", status: 204), response("", status: 204)])
        let client = EightClient(transport: transport, now: { testNow })
        let level = try PodTemperature.level(fahrenheit: 68)
        try await client.control(.temperature(level), credentials: credentials(),
            cachedToken: AccessToken(value: "token", expiresAt: testNow.addingTimeInterval(1000), userID: "uid")) { _ in }
        let requests = await transport.recorded()
        let body = try JSONSerialization.jsonObject(with: requests[1].httpBody!) as! [String: Int]
        XCTAssertEqual(body["currentLevel"], -58)
    }
}
