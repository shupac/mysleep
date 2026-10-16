import Foundation

enum SleepSummary {
    static func text(_ envelope: ReportEnvelope, now: Date = Date()) -> String {
        let r = envelope.report
        let date = ReportEnvelope.date(r.wakeTime)!
        let format = DateFormatter(); format.timeZone = TimeZone(identifier: r.timezone)
        format.locale = Locale(identifier: "en_US"); format.dateFormat = "MMMM d"
        var parts = [envelope.isStale(now: now) ? "This is an older or cached report." : "",
                     "For your sleep ending \(format.string(from: date)), you slept \(duration(r.totalSleepSeconds))."]
        if let score = r.score { parts.append("Your sleep score was \(Int(score.rounded())).") }
        if let deep = r.stages.deep.seconds, let rem = r.stages.rem.seconds {
            parts.append("Deep sleep was \(duration(deep)), and REM sleep was \(duration(rem)).")
        }
        if let heart = r.heartRateBpm { parts.append("Your sleeping heart rate was \(Int(heart.rounded())) beats per minute.") }
        if let hrv = r.hrvMs { parts.append("HRV was \(Int(hrv.rounded())) milliseconds.") }
        if !r.missingMetrics.isEmpty { parts.append("Some measurements are unavailable.") }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded()), hours = Int((seconds / 60).rounded()) / 60
        let h = hours > 0 ? "\(hours) \(hours == 1 ? "hour" : "hours")" : ""
        let m = minutes % 60 > 0 || hours == 0 ? "\(minutes % 60) \(minutes % 60 == 1 ? "minute" : "minutes")" : ""
        return [h, m].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
