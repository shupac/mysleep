import SwiftUI
import WidgetKit

struct SleepScoreEntry: TimelineEntry {
    let date: Date
    let snapshot: SleepScoreSnapshot?
    var score: String { snapshot?.scoreText ?? "—" }
    var saved: Bool { snapshot?.isStale(at: date) == true }
    var detail: String {
        guard let snapshot else { return "Open MySleep" }
        return (saved ? "Saved · " : "") + snapshot.sleepDateText
    }
    var accessibilityText: String {
        guard let snapshot else { return "No sleep score. Open MySleep to refresh." }
        return "Sleep score \(score), \(snapshot.sleepDateText)." + (saved ? " Saved report. Tap to refresh." : "")
    }
}

struct SleepScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepScoreEntry {
        SleepScoreEntry(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (SleepScoreEntry) -> Void) {
        completion(SleepScoreEntry(date: Date(), snapshot: SleepScoreSnapshotStorage().read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepScoreEntry>) -> Void) {
        let now = Date(), snapshot = SleepScoreSnapshotStorage().read()
        var entries = [SleepScoreEntry(date: now, snapshot: snapshot)]
        // Change the saved-data label on time even if the app hasn't run again.
        if let snapshot {
            let expiry = min(snapshot.fetchedAt.addingTimeInterval(901), snapshot.wakeTime.addingTimeInterval(36 * 3600 + 1))
            if expiry > now { entries.append(SleepScoreEntry(date: expiry, snapshot: snapshot)) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct SleepScoreComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SleepScoreEntry
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("Sleep \(entry.score)\(entry.saved ? " · Saved" : "")")
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill").widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sleep score \(entry.score)").font(.headline)
                        Text(entry.detail).font(.caption)
                    }
                }
            case .accessoryCorner:
                Text(entry.score).font(.title2.bold()).widgetAccentable()
                    .widgetLabel { Text("Sleep · \(entry.detail)") }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: entry.saved ? "clock" : "moon.zzz.fill").font(.caption2)
                        Text(entry.score).font(.title2.bold()).minimumScaleFactor(0.6)
                    }
                }
                .widgetLabel { Text("Sleep · \(entry.detail)") }
            }
        }
        .privacySensitive()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityText)
        .containerBackground(for: .widget) { Color.clear }
    }
}

@main
struct SleepScoreComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SleepScoreSnapshotStorage.widgetKind, provider: SleepScoreProvider()) {
            SleepScoreComplicationView(entry: $0)
        }
        .configurationDisplayName("Sleep Score")
        .description("Your latest Eight Sleep score. Open MySleep to refresh.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
