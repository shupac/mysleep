import Foundation

struct ScriptedTransport: HTTPTransport {
    let reply: HTTPResult
    func send(_ request: URLRequest) async throws -> HTTPResult { reply }
}
@main struct DiagnosticsTests {
    static func main() async throws {
        let secret = "never-echo-this-token"
        let payload = Data("""
        {"modelVersion":"v3","days":[{"day":"2026-10-15","sleepDuration":27000,"presenceEnd":"2026-10-15T14:00:00Z","sessions":[{"id":"private-session"}]}]}
        """.utf8)
        let transport = DiagnosticTransport(underlying: ScriptedTransport(reply: HTTPResult(data: payload, status: 200)))
        var request = URLRequest(url: URL(string: "https://client-api.8slp.net/v1/users/private-user/trends?tz=America/Los_Angeles")!)
        request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        _ = try await transport.send(request)
        let diagnostics = await transport.snapshot()
        let text = String(decoding: try JSONSerialization.data(withJSONObject: diagnostics), as: UTF8.self)
        precondition(!text.contains(secret) && !text.contains("private-user") && !text.contains("private-session"))
        precondition(!text.contains("27000"))
        precondition(diagnostics[0]["path"] as? String == "/v1/users/{userId}/trends")
        precondition((diagnostics[0]["days"] as? [[String: Any]])?[0]["hasSleepDuration"] as? Bool == true)
        await transport.clear()
        var login = URLRequest(url: URL(string: "https://auth-api.8slp.net/v1/tokens")!)
        login.httpMethod = "POST"
        login.httpBody = Data("password=private-password".utf8)
        _ = try await transport.send(login)
        let authDiagnostics = await transport.snapshot()
        precondition(authDiagnostics[0]["days"] == nil)
        print("Diagnostics redaction and auth-body exclusion passed.")
    }
}
