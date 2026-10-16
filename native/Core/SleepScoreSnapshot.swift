import Foundation
#if os(watchOS)
import WidgetKit
#endif

/// Only the score and report dates are shared with the complication, never credentials.
struct SleepScoreSnapshot: Codable, Equatable {
    let score: Double?
    let wakeTime: Date
    let fetchedAt: Date
    let timezone: String
    let stale: Bool

    init?(_ envelope: ReportEnvelope) {
        guard let wake = ReportEnvelope.date(envelope.report.wakeTime),
              let fetched = ReportEnvelope.date(envelope.fetchedAt) else { return nil }
        let value = envelope.report.score
        score = value.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        wakeTime = wake; fetchedAt = fetched
        timezone = envelope.report.timezone; stale = envelope.stale
    }
    var scoreText: String { score.map { String(Int($0.rounded())) } ?? "—" }
    func isStale(at date: Date) -> Bool {
        stale || date.timeIntervalSince(fetchedAt) > 900 || date.timeIntervalSince(wakeTime) > 36 * 3600
    }
    var sleepDateText: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: wakeTime)
    }
}

struct SleepScoreSnapshotStorage {
    static let widgetKind = "SleepScoreComplication"
    let url: URL?
    init(url: URL? = Self.sharedURL) { self.url = url }
    static var sharedURL: URL? {
        #if os(watchOS)
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SleepAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("sleep-score.json")
        #else
        return nil
        #endif
    }
    func read() -> SleepScoreSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SleepScoreSnapshot.self, from: data)
    }
    func write(_ envelope: ReportEnvelope) throws {
        guard let url, let snapshot = SleepScoreSnapshot(envelope), read() != snapshot else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(watchOS)
        options.insert(.completeFileProtection)
        #endif
        try JSONEncoder().encode(snapshot).write(to: url, options: options)
        var file = url
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        try file.setResourceValues(resource)
        reload()
    }
    func clear() throws {
        if let url, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        reload()
    }
    private func reload() {
        #if os(watchOS)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        #endif
    }
}
