import Foundation
@testable import SleepCore

let testNow = ISO8601DateFormatter().date(from: "2026-10-14T14:00:00Z")!
func fixture(_ name: String = "trends") throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
}
func credentials(_ email: String = "you@example.com") throws -> Credentials {
    try Credentials(email: email, password: "password +&=ü", timezone: "America/Los_Angeles")
}
func response(_ json: String, status: Int = 200, retry: String? = nil) -> HTTPResult {
    HTTPResult(data: Data(json.utf8), status: status, retryAfter: retry)
}
let loginResponse = response("{\"access_token\":\"new-token\",\"expires_in\":3600,\"userId\":\"uid\"}")
actor MockTransport: HTTPTransport {
    var responses: [HTTPResult]
    var requests: [URLRequest] = []
    let delay: Duration
    init(_ responses: [HTTPResult], delay: Duration = .zero) { self.responses = responses; self.delay = delay }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        if delay > .zero { try await Task.sleep(for: delay) }
        guard !responses.isEmpty else { throw SleepError.unavailable }
        return responses.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}
final class MemorySession: SessionStorage {
    var saved: SavedSession?
    func load() throws -> SavedSession? { saved }
    func save(_ session: SavedSession) throws { saved = session }
    func clear() throws { saved = nil }
}
final class MemoryReports: ReportStorage {
    var value: ReportEnvelope?
    func read() throws -> ReportEnvelope? { value }
    func write(_ report: ReportEnvelope) throws { value = report }
    func clear() throws { value = nil }
}
actor TokenRecorder {
    var values: [AccessToken?] = []
    func add(_ token: AccessToken?) { values.append(token) }
    func all() -> [AccessToken?] { values }
}
