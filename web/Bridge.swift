import Foundation

// Compiled in the same module as native/Core: the web client exercises the
// production client, parser and service, without reading the native Keychain.
final class WebSession: SessionStorage {
    var value: SavedSession?
    func load() throws -> SavedSession? { value }
    func save(_ session: SavedSession) throws { value = session }
    func clear() throws { value = nil }
}
final class WebReports: ReportStorage {
    var value: ReportEnvelope?
    func read() throws -> ReportEnvelope? { value }
    func write(_ report: ReportEnvelope) throws { value = report }
    func clear() throws { value = nil }
}
actor DiagnosticTransport: HTTPTransport {
    private let underlying: HTTPTransport
    private var entries: [[String: Any]] = []
    init(underlying: HTTPTransport = URLSessionTransport()) { self.underlying = underlying }
    func clear() { entries = [] }
    func snapshot() -> [[String: Any]] { entries }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let started = Date()
        var event: [String: Any] = [
            "method": request.httpMethod ?? "GET",
            "host": request.url?.host ?? "",
            "path": (request.url?.path ?? "").replacingOccurrences(
                of: "/users/[^/]+", with: "/users/{userId}", options: .regularExpression)
        ]
        do {
            let result = try await underlying.send(request)
            event["status"] = result.status
            event["milliseconds"] = Int(Date().timeIntervalSince(started) * 1000)
            // Structural diagnostics only. Never return headers, tokens, auth
            // response bodies, account IDs, or raw sensor data to the browser.
            if request.url?.path.hasSuffix("/trends") == true,
               let root = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any] {
                event["model"] = root["modelVersion"] as? String
                let days = root["days"] as? [[String: Any]] ?? []
                event["days"] = days.map { day -> [String: Any] in
                    ["date": day["day"] as? String ?? "unknown",
                     "incomplete": day["incomplete"] as? Bool ?? false,
                     "hasPresenceEnd": day["presenceEnd"] is String,
                     "hasSleepDuration": day["sleepDuration"] is NSNumber,
                     "hasSleepDurationSeconds": day["sleepDurationSeconds"] is NSNumber,
                     "fields": day.keys.sorted()]
                }
            }
            entries.append(event)
            return result
        } catch {
            event["error"] = "Connection failed or timed out."
            event["milliseconds"] = Int(Date().timeIntervalSince(started) * 1000)
            entries.append(event)
            throw error
        }
    }
}

struct WebCommand: Decodable {
    let command: String
    var email: String?
    var password: String?
    var timezone: String?
    var action: String?
    var fahrenheit: Double?
}

#if !WEB_TESTING
@main
#endif
struct WebBridge {
    static func object<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    static func main() async {
        let transport = DiagnosticTransport()
        let secure = WebSession(), cache = WebReports()
        let service = SleepService(secure: secure, cache: cache,
                                   client: EightClient(transport: transport),
                                   scoreStorage: SleepScoreSnapshotStorage(url: nil))
        var demo = false
        while let line = readLine() {
            await transport.clear()
            var output: [String: Any] = ["ok": true]
            do {
                let input = try JSONDecoder().decode(WebCommand.self, from: Data(line.utf8))
                switch input.command {
                case "configure":
                    let credentials = try Credentials(email: input.email ?? "", password: input.password ?? "",
                                                      timezone: input.timezone ?? "")
                    try await service.configure(credentials)
                    demo = false
                    output["report"] = try await object(service.latest(force: true))
                case "report":
                    guard !demo else { throw SleepError.notConfigured }
                    output["report"] = try await object(service.latest(force: true))
                case "status":
                    guard !demo else { throw SleepError.notConfigured }
                    let pod = try await service.podStatus()
                    output["pod"] = ["level": pod.currentLevel, "mode": pod.currentState.type,
                                     "fahrenheit": PodTemperature.fahrenheit(level: pod.currentLevel) ?? 80]
                case "control":
                    guard !demo else { throw SleepError.notConfigured }
                    let action: PodAction
                    switch input.action {
                    case "on": action = .turnOn
                    case "off": action = .turnOff
                    case "temperature": action = .temperature(try PodTemperature.level(fahrenheit: input.fahrenheit ?? .nan))
                    default: throw SleepError.invalidConfiguration
                    }
                    try await service.control(action)
                    output["message"] = input.action == "off"
                        ? "Off command accepted. Report processing is managed by Eight Sleep."
                        : "Command accepted. Refresh Pod status to confirm."
                case "demo":
                    try await service.signOut()
                    demo = true
                    let url = URL(fileURLWithPath: CommandLine.arguments[1])
                    let report = try JSONDecoder().decode(ReportEnvelope.self, from: Data(contentsOf: url))
                    output["report"] = try object(report)
                case "disconnect":
                    try await service.signOut()
                    demo = false
                case "state": break
                default: throw SleepError.invalidConfiguration
                }
            } catch {
                output["ok"] = false
                output["error"] = (error as? SleepError)?.localizedDescription ?? "The local client couldn’t complete this operation."
            }
            output["configured"] = (try? await service.configuration()) != nil
            output["demo"] = demo
            output["diagnostics"] = await transport.snapshot()
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) { print(json) }
            else { print("{\"ok\":false,\"error\":\"Local response encoding failed.\"}") }
            fflush(stdout)
        }
    }
}
