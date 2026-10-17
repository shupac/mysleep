import SwiftUI

@MainActor
final class SleepStore: ObservableObject {
    @Published private(set) var report: ReportEnvelope?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var isConfigured = false
    @Published private(set) var email = ""
    @Published private(set) var timezone = TimeZone.current.identifier
    private let service: SleepService
    private let demo: Bool
    private var generation = 0
    var isOffline: Bool { report?.stale == true }

    init(service: SleepService = .shared) {
        self.service = service
        #if DEBUG
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        if demo, let url = Bundle.main.url(forResource: "demo", withExtension: "json"),
           let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(ReportEnvelope.self, from: data) {
            let stale = ProcessInfo.processInfo.arguments.contains("--demo-stale")
            report = ReportEnvelope(report: saved.report,
                fetchedAt: ISO8601DateFormatter().string(from: stale ? Date().addingTimeInterval(-86400) : Date()),
                stale: stale, warning: stale ? "Showing saved data. Couldn’t reach Eight Sleep." : nil)
            isConfigured = true
            if ProcessInfo.processInfo.arguments.contains("--demo-empty") { report = nil; isConfigured = false }
        }
        #else
        demo = false
        #endif
    }
    func start(loadReport: Bool = true) async {
        guard !demo else { return }
        do {
            if let config = try await service.configuration() {
                isConfigured = true; email = config.email; timezone = config.timezone
                if report == nil { report = try await service.cached() }
                if loadReport { await refresh() }
            } else { isConfigured = false }
        } catch { self.error = error.localizedDescription }
    }
    func refresh(force: Bool = false) async {
        guard !demo, !isLoading, isConfigured else { return }
        let version = generation
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.latest(force: force)
            guard generation == version else { return }
            report = result
            error = result.warning
        } catch is CancellationError { }
        catch { if generation == version { self.error = error.localizedDescription } }
    }
    func save(email: String, password: String, timezone: String) async throws {
        let credentials = try Credentials(email: email, password: password, timezone: timezone)
        generation += 1
        try await service.configure(credentials)
        self.email = credentials.email; self.timezone = credentials.timezone
        report = nil; error = nil; isConfigured = true
    }
    func disconnect() async throws {
        generation += 1
        try await service.signOut()
        report = nil; error = nil; isConfigured = false; email = ""
    }
}
