import Foundation
import CoreFoundation


// Projects only sleep metrics; performance windows and raw responses aren't kept.
enum ReportParser {
    static func parse(_ data: Data, timezone: String, now: Date = Date()) throws -> SleepReport {
        guard TimeZone(identifier: timezone) != nil,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let days = root["days"] as? [[String: Any]] else { throw SleepError.invalidResponse }
        let completed = days.filter { day in
            guard day["incomplete"] as? Bool != true,
                  let start = date(day["presenceStart"]), let end = date(day["presenceEnd"]),
                  start < end, end <= now, let total = sleepDuration(day), total > 0 else { return false }
            return true
        }.sorted { date($0["presenceEnd"])! > date($1["presenceEnd"])! }
        guard let day = completed.first else { throw SleepError.noCompletedReport }
        let start = date(day["presenceStart"])!, end = date(day["presenceEnd"])!
        let total = sleepDuration(day)!
        guard total <= end.timeIntervalSince(start) + 60 else { throw SleepError.invalidResponse }
        var stages: [String: Double] = [:]
        for stage in day["stages"] as? [[String: Any]] ?? [] {
            guard let name = (stage["stage"] as? String)?.lowercased(),
                  ["deep", "rem", "light", "awake"].contains(name), let value = number(stage["duration"]) else { continue }
            stages[name, default: 0] += value
        }
        // The captured v3 response supplies aggregate stage durations in seconds.
        if day["stages"] == nil {
            for name in ["deep", "rem", "light"] {
                stages[name] = number(day[name + "Duration"])
            }
        }
        let names = ["deep", "rem", "light"]
        let stageSum = names.reduce(0) { $0 + (stages[$1] ?? 0) }
        // Stage seconds must reconcile with the total sleep duration before display.
        let validStages = names.allSatisfy { stages[$0] != nil }
            && abs(stageSum - total) <= max(60, total * 0.02)
        func stage(_ name: String) -> SleepStage {
            guard validStages, let seconds = stages[name] else { return SleepStage(seconds: nil, percent: nil) }
            return SleepStage(seconds: seconds, percent: (seconds / total * 1000).rounded() / 10)
        }
        let score = number(day["score"]).flatMap { $0 <= 100 ? $0 : nil }
        // Never use sleepQualityScore.hrv.score as raw HRV milliseconds.
        let hrv = number(day["hrvMs"]) ?? number(day["hrv"]) ?? qualityCurrent(day, "hrv")
            ?? seriesMean(day["sessions"], key: "hrv", start: start, end: end)
        let hrvScore = ((day["sleepQualityScore"] as? [String: Any])?["hrv"] as? [String: Any])
            .flatMap { number($0["score"]) }.flatMap { $0 <= 100 ? $0 : nil }
        let snoring = (number(day["snoringDurationSeconds"]) ?? number(day["snoreDuration"]))
            .flatMap { $0 <= total ? $0 : nil }
        let reportedAwake = (validStages ? stages["awake"] : nil)
            ?? sessionAwake(day["sessions"], sleepSeconds: total)
        let awake = reportedAwake.flatMap { $0 <= end.timeIntervalSince(start) - total + 60 ? $0 : nil }
        let sleepStart = date(day["sleepStart"]), sleepEnd = date(day["sleepEnd"])
        let validSleepTimes = sleepStart != nil && sleepEnd != nil && sleepStart! < sleepEnd!
            && sleepStart! >= start && sleepEnd! <= end
        let bedtime = validSleepTimes ? sleepStart! : start
        let wakeTime = validSleepTimes ? sleepEnd! : end
        let heart = positive(day["heartRate"]) ?? qualityCurrent(day, "heartRate")
        let respiratory = positive(day["respiratoryRate"]) ?? qualityCurrent(day, "respiratoryRate")
        var missing: [String] = []
        if score == nil { missing.append("Sleep score") }
        if !validStages { missing += ["Deep sleep", "REM sleep", "Light sleep"] }
        if heart == nil { missing.append("Heart rate") }
        if hrv == nil { missing.append("HRV milliseconds") }
        if respiratory == nil { missing.append("Respiratory rate") }
        if awake == nil { missing.append("Awake time") }
        if snoring == nil { missing.append("Snoring") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone); formatter.dateFormat = "yyyy-MM-dd"
        return SleepReport(schemaVersion: 1, date: formatter.string(from: wakeTime), timezone: timezone,
                           bedtime: iso(bedtime), wakeTime: iso(wakeTime), score: score, totalSleepSeconds: total,
                           stages: SleepStages(deep: stage("deep"), rem: stage("rem"), light: stage("light")),
                           heartRateBpm: heart, hrvMs: hrv, respiratoryRate: respiratory, awakeSeconds: awake,
                           snoringSeconds: snoring, missingMetrics: missing, hrvScore: hrvScore,
                           timesArePresence: !validSleepTimes)
    }
    private static func sleepDuration(_ day: [String: Any]) -> Double? {
        number(day["sleepDurationSeconds"]) ?? number(day["sleepDuration"])
    }
    private static func sessionAwake(_ raw: Any?, sleepSeconds: Double) -> Double? {
        guard let sessions = raw as? [[String: Any]], !sessions.isEmpty else { return nil }
        var sleep = 0.0, awake = 0.0
        for session in sessions {
            guard let summary = session["stageSummary"] as? [String: Any],
                  let sessionSleep = number(summary["sleepDuration"]),
                  let sessionAwake = number(summary["awakeDuration"]),
                  let out = number(summary["outDuration"]),
                  let duration = number(summary["totalDuration"]),
                  abs(sessionSleep + sessionAwake + out - duration) <= 60 else { return nil }
            sleep += sessionSleep; awake += sessionAwake
        }
        // Require complete, matching session coverage. Time out of bed is not
        // awake time, and missing session summaries must not become zero.
        guard abs(sleep - sleepSeconds) <= max(60, sleepSeconds * 0.02) else { return nil }
        return awake
    }
    private static func qualityCurrent(_ day: [String: Any], _ key: String) -> Double? {
        guard let quality = day["sleepQualityScore"] as? [String: Any],
              let metric = quality[key] as? [String: Any], metric["available"] as? Bool == true else { return nil }
        return positive(metric["current"])
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue >= 0 else { return nil }
        return n.doubleValue
    }
    private static func positive(_ value: Any?) -> Double? { number(value).flatMap { $0 > 0 ? $0 : nil } }
    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String, s.contains("T"), s.hasSuffix("Z") || s.range(of: "[+-][0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        return ReportEnvelope.date(s)
    }
    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func seriesMean(_ raw: Any?, key: String, start: Date, end: Date) -> Double? {
        var values: [Date: Double] = [:]
        for session in raw as? [[String: Any]] ?? [] {
            let series = (session["timeseries"] as? [String: Any])?[key] as? [[Any]] ?? []
            for sample in series where sample.count >= 2 {
                guard let time = date(sample[0]), time >= start, time <= end, let value = positive(sample[1]) else { continue }
                values[time] = value
            }
        }
        return values.isEmpty ? nil : (values.values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
    }
}
