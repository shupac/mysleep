// Swift port of eightctl's auth.go, transport.go, eightsleep.go and metrics.go.
// Existing API contract only. Attribution and limitations: docs/provenance.md.
import Foundation

struct EightClient {
    private let transport: HTTPTransport
    private let now: () -> Date
    private let wait: (TimeInterval) async throws -> Void
    init(transport: HTTPTransport = URLSessionTransport(), now: @escaping () -> Date = Date.init,
         wait: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.transport = transport; self.now = now; self.wait = wait
    }
    static let clientID = "0894c7f33bb94800a03f1f4df13a4f38"
    static let clientSecret = "f0954a3ed5763ba3d06834c73731a32f15f168f47d4f164751275def86db0c76"
    private let base = "https://client-api.8slp.net/v1"

    func fetch(credentials: Credentials, cachedToken: AccessToken?,
               saveToken: @escaping (AccessToken?) async throws -> Void) async throws -> Data {
        var token = try await authenticatedToken(credentials: credentials, cachedToken: cachedToken, saveToken: saveToken)
        let userID = token.userID
        let zone = TimeZone(identifier: credentials.timezone)!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let from = calendar.date(byAdding: .day, value: -14, to: now())!
        let formatter = DateFormatter(); formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        let items = ["from": formatter.string(from: from), "to": formatter.string(from: now()),
                     "tz": credentials.timezone, "include-main": "false", "include-all-sessions": "true", "model-version": "v3", "consistent-read": "true"]
        var parts = URLComponents()
        parts.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "/?#%")
        guard let encodedID = userID?.addingPercentEncoding(withAllowedCharacters: allowed) else { throw SleepError.invalidResponse }
        return try await get(path: "/users/\(encodedID)/trends?\(parts.percentEncodedQuery!)",
                             credentials: credentials, token: &token, saveToken: saveToken)
    }
    private func authenticatedToken(credentials: Credentials, cachedToken: AccessToken?,
                                    saveToken: @escaping (AccessToken?) async throws -> Void) async throws -> AccessToken {
        var token: AccessToken
        if let cachedToken, cachedToken.expiresAt > now() { token = cachedToken }
        else { token = try await login(credentials); try await saveToken(token) }
        var userID = token.userID
        if userID == nil {
            let data = try await get(path: "/users/me", credentials: credentials, token: &token, saveToken: saveToken)
            struct Me: Decodable { struct User: Decodable { let userId: String }; let user: User }
            guard let me = try? JSONDecoder().decode(Me.self, from: data), !me.user.userId.isEmpty else { throw SleepError.invalidResponse }
            userID = me.user.userId
            token.userID = userID
            try await saveToken(token)
        }
        return token
    }
    func podStatus(credentials: Credentials, cachedToken: AccessToken?,
                   saveToken: @escaping (AccessToken?) async throws -> Void) async throws -> PodStatus {
        var token = try await authenticatedToken(credentials: credentials, cachedToken: cachedToken, saveToken: saveToken)
        let data = try await request(url: podURL(token), credentials: credentials, token: &token, saveToken: saveToken)
        guard let status = try? JSONDecoder().decode(PodStatus.self, from: data),
              (-100...100).contains(status.currentLevel), !status.currentState.type.isEmpty else { throw SleepError.invalidResponse }
        return status
    }
    func control(_ action: PodAction, credentials: Credentials, cachedToken: AccessToken?,
                 saveToken: @escaping (AccessToken?) async throws -> Void) async throws {
        if case .temperature(let level) = action, !(-100...100).contains(level) { throw SleepError.invalidTemperature }
        var token = try await authenticatedToken(credentials: credentials, cachedToken: cachedToken, saveToken: saveToken)
        let url = try podURL(token)
        func state(_ type: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["currentState": ["type": type]])
        }
        switch action {
        case .temperature(let level):
            _ = try await request(url: url, method: "PUT", body: state("smart"), retryTransient: false,
                                  credentials: credentials, token: &token, saveToken: saveToken)
            do {
                _ = try await request(url: url, method: "PUT", body: JSONSerialization.data(withJSONObject: ["currentLevel": level]),
                                      retryTransient: false, credentials: credentials, token: &token, saveToken: saveToken)
            } catch is CancellationError { throw CancellationError() }
            catch { throw SleepError.partialTemperatureChange }
        case .endSleep:
            // Official app capture (2026-10-16): stop the incomplete interval,
            // rather than treating temperature power as sleep tracking state.
            var parts = URLComponents(url: url.deletingLastPathComponent().appendingPathComponent("intervals"), resolvingAgainstBaseURL: false)!
            parts.host = "client-api.8slp.net"
            let clientURL = parts.url!
            let data = try await request(url: clientURL, credentials: credentials, token: &token, saveToken: saveToken)
            struct Intervals: Decodable {
                struct Interval: Decodable { let id: String; let ts: String; let incomplete: Bool? }
                let intervals: [Interval]
            }
            guard let result = try? JSONDecoder().decode(Intervals.self, from: data) else { throw SleepError.invalidResponse }
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            let candidates = result.intervals.compactMap { interval -> (String, Date)? in
                guard interval.incomplete == true,
                      let start = formatter.date(from: interval.ts) ?? plain.date(from: interval.ts),
                      start <= now(), now().timeIntervalSince(start) < 36 * 3600 else { return nil }
                return (interval.id, start)
            }
            guard let interval = candidates.max(by: { $0.1 < $1.1 }) else { throw SleepError.noActiveSleep }
            _ = try await request(url: clientURL.appendingPathComponent(interval.0), method: "PUT",
                                  body: JSONSerialization.data(withJSONObject: ["edit": "stop"]), retryTransient: false,
                                  credentials: credentials, token: &token, saveToken: saveToken)
        case .turnOn, .turnOff:
            _ = try await request(url: url, method: "PUT", body: state(action == .turnOn ? "smart" : "off"), retryTransient: false,
                                  credentials: credentials, token: &token, saveToken: saveToken)
        }
    }
    private func podURL(_ token: AccessToken) throws -> URL {
        var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "/?#%")
        guard let id = token.userID?.addingPercentEncoding(withAllowedCharacters: allowed), !id.isEmpty,
              let url = URL(string: "https://app-api.8slp.net/v1/users/\(id)/temperature") else { throw SleepError.invalidResponse }
        return url
    }
    private func login(_ credentials: Credentials) async throws -> AccessToken {
        var request = URLRequest(url: URL(string: "https://auth-api.8slp.net/v1/tokens")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let values = ["grant_type": "password", "username": credentials.email, "password": credentials.password,
                      "client_id": Self.clientID, "client_secret": Self.clientSecret]
        request.httpBody = Data(values.sorted { $0.key < $1.key }.map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }.joined(separator: "&").utf8)
        try Task.checkCancellation()
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            if response.status == 429 { throw SleepError.rateLimited }
            if response.status >= 500 { throw SleepError.unavailable }
            throw SleepError.authentication
        }
        struct Login: Decodable { let access_token: String; let expires_in: Double?; let userId: String? }
        guard let data = try? JSONDecoder().decode(Login.self, from: response.data), !data.access_token.isEmpty else { throw SleepError.invalidResponse }
        let seconds = (data.expires_in ?? 0) == 0 ? 3600 : data.expires_in!
        guard seconds.isFinite, seconds > 0 else { throw SleepError.invalidResponse }
        return AccessToken(value: data.access_token, expiresAt: now().addingTimeInterval(max(0, seconds - 60)),
                           userID: data.userId.flatMap { $0.isEmpty ? nil : $0 })
    }
    private func get(path: String, credentials: Credentials, token: inout AccessToken,
                     saveToken: @escaping (AccessToken?) async throws -> Void) async throws -> Data {
        try await request(url: URL(string: base + path)!, credentials: credentials, token: &token, saveToken: saveToken)
    }
    private func request(url: URL, method: String = "GET", body: Data? = nil, retryTransient: Bool = true,
                         credentials: Credentials, token: inout AccessToken,
                         saveToken: @escaping (AccessToken?) async throws -> Void) async throws -> Data {
        var renewed = false
        for attempt in 0..<3 {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("okhttp/4.9.3", forHTTPHeaderField: "User-Agent")
            let response: HTTPResult
            do { response = try await transport.send(request) }
            catch is CancellationError { throw CancellationError() }
            catch { throw method == "GET" ? error : SleepError.controlUnconfirmed }
            switch response.status {
            case 200..<300: return response.data
            case 401:
                try await saveToken(nil)
                guard !renewed, attempt < 2 else { throw SleepError.authentication }
                let targetID = token.userID
                token = try await login(credentials)
                // The principal remains the same after reauth; retain discovered ID.
                if token.userID == nil { token.userID = targetID }
                try await saveToken(token); renewed = true
            case 429, 500...599:
                let error: SleepError = response.status == 429 ? .rateLimited : (method == "GET" ? .unavailable : .controlUnconfirmed)
                guard retryTransient else { throw error }
                guard attempt < 2 else { throw error }
                let delay = Self.retryDelay(response.retryAfter, now: now(), fallback: Double(attempt + 1))
                guard delay <= 3 else { throw error }
                try await wait(delay)
            default: throw SleepError.unavailable
            }
        }
        throw SleepError.unavailable
    }
    static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))!
    }
    static func retryDelay(_ header: String?, now: Date, fallback: Double) -> Double {
        guard let header else { return fallback }
        if let seconds = Double(header), seconds.isFinite { return max(0, seconds) }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return format.date(from: header).map { max(0, $0.timeIntervalSince(now)) } ?? fallback
    }
}
