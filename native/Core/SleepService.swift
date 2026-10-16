import Foundation

/// One instance per process, shared by the UI and Siri. Coalesces simultaneous
/// fetches; generations prevent an old request from overwriting a new account.
actor SleepService {
    static let shared = SleepService()
    private let secure: SessionStorage
    private let cache: ReportStorage
    private let client: EightClient
    private let now: () -> Date
    private let scoreStorage: SleepScoreSnapshotStorage
    private var revision = 0
    private var pending: (id: UUID, task: Task<ReportEnvelope, Error>)?
    private var pendingPod: (id: UUID, task: Task<PodStatus?, Error>)?
    private var retryAfter: Date?
    private var lastError: SleepError?
    private var reportNeedsRefresh = false

    init(secure: SessionStorage = KeychainSessionStorage(), cache: ReportStorage = FileReportStorage(),
         client: EightClient = EightClient(), scoreStorage: SleepScoreSnapshotStorage = SleepScoreSnapshotStorage(), now: @escaping () -> Date = Date.init) {
        self.secure = secure; self.cache = cache; self.client = client; self.scoreStorage = scoreStorage; self.now = now
    }
    func configuration() throws -> Credentials? { try secure.load()?.credentials }
    func cached() throws -> ReportEnvelope? {
        guard try secure.load() != nil else { return nil }
        guard let report = try? cache.read() else { return nil }
        return publish(report)
    }
    func configure(_ credentials: Credentials) throws {
        pending?.task.cancel(); pending = nil
        pendingPod?.task.cancel(); pendingPod = nil; revision += 1
        // Never display an old account's report after switching credentials.
        try scoreStorage.clear()
        try cache.clear()
        try secure.save(SavedSession(credentials: credentials, token: nil))
        retryAfter = nil; lastError = nil
    }
    func signOut() throws {
        pending?.task.cancel(); pending = nil
        pendingPod?.task.cancel(); pendingPod = nil; revision += 1
        try scoreStorage.clear()
        try cache.clear()
        try secure.clear()
        retryAfter = nil; lastError = nil
    }
    func latest(force: Bool = false) async throws -> ReportEnvelope {
        if let pod = pendingPod {
            _ = await pod.task.result
            if pendingPod?.id == pod.id { pendingPod = nil }
        }
        try Task.checkCancellation()
        guard let saved = try secure.load() else { throw SleepError.notConfigured }
        if let pending { return try await pending.task.value }
        let cached = try? cache.read()
        if let retryAfter, now() < retryAfter {
            if let cached { return fallback(cached, error: lastError ?? .unavailable) }
            throw lastError ?? .unavailable
        }
        if !force, !reportNeedsRefresh, lastError == nil, let cached, let fetched = ReportEnvelope.date(cached.fetchedAt), now().timeIntervalSince(fetched) < 300 {
            return publish(cached)
        }
        let version = revision
        let id = UUID()
        let task = Task { try await self.load(saved, version: version, cached: cached) }
        pending = (id, task)
        defer { if pending?.id == id { pending = nil } }
        return try await task.value
    }
    func podStatus() async throws -> PodStatus {
        guard let status = try await podOperation(nil) else { throw SleepError.invalidResponse }
        return status
    }
    func control(_ action: PodAction) async throws {
        _ = try await podOperation(action)
    }
    private func podOperation(_ action: PodAction?) async throws -> PodStatus? {
        guard pendingPod == nil else { throw SleepError.controlsBusy }
        let requestedRevision = revision
        if let report = pending {
            _ = await report.task.result
            if pending?.id == report.id { pending = nil }
        }
        try Task.checkCancellation()
        guard requestedRevision == revision else { throw CancellationError() }
        guard pendingPod == nil else { throw SleepError.controlsBusy }
        guard let saved = try secure.load() else { throw SleepError.notConfigured }
        let version = revision, id = UUID()
        let task = Task<PodStatus?, Error> {
            let save: (AccessToken?) async throws -> Void = { token in
                try self.persist(token, saved: saved, version: version)
            }
            let status: PodStatus?
            if let action {
                try await self.client.control(action, credentials: saved.credentials, cachedToken: saved.token, saveToken: save)
                if action == .endSleep { self.reportNeedsRefresh = true; self.retryAfter = nil; self.lastError = nil }
                status = nil
            } else {
                status = try await self.client.podStatus(credentials: saved.credentials, cachedToken: saved.token, saveToken: save)
            }
            try Task.checkCancellation()
            guard version == self.revision else { throw CancellationError() }
            return status
        }
        pendingPod = (id, task)
        defer { if pendingPod?.id == id { pendingPod = nil } }
        return try await task.value
    }
    private func load(_ saved: SavedSession, version: Int, cached: ReportEnvelope?) async throws -> ReportEnvelope {
        do {
            let data = try await client.fetch(credentials: saved.credentials, cachedToken: saved.token) { token in
                try self.persist(token, saved: saved, version: version)
            }
            try Task.checkCancellation()
            guard version == revision else { throw CancellationError() }
            let report = try ReportParser.parse(data, timezone: saved.credentials.timezone, now: now())
            reportNeedsRefresh = false
            let envelope = ReportEnvelope(report: report, fetchedAt: ISO8601DateFormatter().string(from: now()), stale: false, warning: nil)
            do { try cache.write(envelope) }
            catch { return publish(ReportEnvelope(report: report, fetchedAt: envelope.fetchedAt, stale: false, warning: "Couldn’t save this report for offline viewing.")) }
            retryAfter = nil; lastError = nil
            return publish(envelope)
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard version == revision else { throw CancellationError() }
            let safeError = error as? SleepError ?? .unavailable
            retryAfter = now().addingTimeInterval(60); lastError = safeError
            if let cached { return fallback(cached, error: safeError) }
            throw safeError
        }
    }
    private func persist(_ token: AccessToken?, saved: SavedSession, version: Int) throws {
        try Task.checkCancellation()
        guard version == revision else { throw CancellationError() }
        try secure.save(SavedSession(credentials: saved.credentials, token: token))
    }
    private func publish(_ envelope: ReportEnvelope) -> ReportEnvelope {
        try? scoreStorage.write(envelope)
        return envelope
    }
    private func fallback(_ cached: ReportEnvelope, error: SleepError) -> ReportEnvelope {
        publish(ReportEnvelope(report: cached.report, fetchedAt: cached.fetchedAt, stale: true,
                       warning: "Showing saved data. " + error.localizedDescription))
    }
}
