import Foundation

protocol ReportStorage {
    func read() throws -> ReportEnvelope?
    func write(_ report: ReportEnvelope) throws
    func clear() throws
}
struct FileReportStorage: ReportStorage {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("latest-sleep.json")
    }
    func read() throws -> ReportEnvelope? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let report = try JSONDecoder().decode(ReportEnvelope.self, from: Data(contentsOf: url))
        guard report.report.schemaVersion == 1, report.report.totalSleepSeconds > 0,
              ReportEnvelope.date(report.fetchedAt) != nil, ReportEnvelope.date(report.report.wakeTime) != nil else { return nil }
        return report
    }
    func write(_ report: ReportEnvelope) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(watchOS) || os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try JSONEncoder().encode(report).write(to: url, options: options)
        var file = url
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        try file.setResourceValues(resource)
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
