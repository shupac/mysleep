import Foundation

struct SleepStage: Codable, Equatable {
    let seconds: Double?
    let percent: Double?
}
struct SleepStages: Codable, Equatable {
    let deep: SleepStage
    let rem: SleepStage
    let light: SleepStage
}
struct SleepReport: Codable, Equatable {
    let schemaVersion: Int
    let date: String
    let timezone: String
    let bedtime: String?
    let wakeTime: String
    let score: Double?
    let totalSleepSeconds: Double
    let stages: SleepStages
    let heartRateBpm: Double?
    let hrvMs: Double?
    let respiratoryRate: Double?
    let awakeSeconds: Double?
    let snoringSeconds: Double?
    let missingMetrics: [String]
    let hrvScore: Double?
    let timesArePresence: Bool

    var stageChartTotalSeconds: Double? {
        guard let deep = stages.deep.seconds, let rem = stages.rem.seconds,
              let light = stages.light.seconds else { return nil }
        let total = deep + rem + light + (awakeSeconds ?? 0)
        return total > 0 ? total : nil
    }
    func stageChartPercent(_ seconds: Double?) -> Double? {
        guard let seconds, let total = stageChartTotalSeconds else { return nil }
        return seconds / total * 100
    }
}
struct ReportEnvelope: Codable, Equatable {
    let report: SleepReport
    let fetchedAt: String
    let stale: Bool
    let warning: String?

    func isStale(now: Date = Date()) -> Bool {
        guard let fetched = Self.date(fetchedAt), let wake = Self.date(report.wakeTime) else { return true }
        return stale || now.timeIntervalSince(fetched) > 15 * 60 || now.timeIntervalSince(wake) > 36 * 3600
    }
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
enum Display {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    static func number(_ value: Double?, unit: String, decimals: Int = 0) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.*f", decimals, value) + " " + unit
    }
    static func time(_ value: String?, timezone: String) -> String {
        guard let value, let date = ReportEnvelope.date(value) else { return "—" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        return formatter.string(from: date)
    }
}
