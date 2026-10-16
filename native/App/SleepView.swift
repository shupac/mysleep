import SwiftUI

struct SleepView: View {
    @EnvironmentObject private var store: SleepStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    private let accent = Color(red: 0.52, green: 0.76, blue: 1)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if store.isConfigured {
                        NavigationLink { PodView() } label: { Label("Pod controls", systemImage: "thermometer.medium") }
                            .accessibilityIdentifier("podControls")
                    }
                    if let envelope = store.report {
                        reportView(envelope)
                    } else if store.isLoading {
                        ProgressView("Getting your sleep…").padding(.vertical, 30)
                    } else {
                        Image(systemName: "moon.zzz.fill").font(.largeTitle).foregroundStyle(accent)
                        Text(store.isConfigured ? "No report yet" : "Your sleep, at a glance")
                            .font(.headline).multilineTextAlignment(.center)
                        Text(store.isConfigured ? "Refresh after your sleep has finished." : "Sign in to Eight Sleep in Settings.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let error = store.error {
                        Text(error).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    if store.isConfigured {
                        Button { Task { await store.refresh(force: true) } } label: {
                            Label(store.isLoading ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                        }.disabled(store.isLoading)
                    }
                    Button("Settings", systemImage: "gearshape") { showSettings = true }.disabled(store.isLoading)
                        .font(.caption)
                }.padding(.horizontal, 8).padding(.bottom)
                .frame(maxWidth: 430).frame(maxWidth: .infinity)
            }
            .navigationTitle("MySleep")
            .refreshable { await store.refresh(force: true) }
            .task { await store.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.start() } }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await store.refresh() } }) {
                SettingsView().environmentObject(store)
            }
        }
    }
    @ViewBuilder
    private func reportView(_ envelope: ReportEnvelope) -> some View {
        let r = envelope.report
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 3) {
                if store.isOffline || envelope.isStale(now: context.date) {
                    Label(store.isOffline ? "Offline · saved report" : "Older / cached report", systemImage: "clock")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        Text(wakeDate(r)).font(.caption).foregroundStyle(.secondary)
        VStack(spacing: 0) {
            Text("Overall").font(.headline)
            Text(r.score.map { String(Int($0.rounded())) } ?? "—")
                .font(.system(size: 54, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                .minimumScaleFactor(0.7).accessibilityLabel("Sleep score \(r.score.map { String(Int($0)) } ?? "unavailable")")
            Text("SLEEP SCORE").font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(10)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        VStack(spacing: 9) {
            Text("Biometrics").font(.headline)
            metric("HR", Display.number(r.heartRateBpm, unit: "bpm"))
            metric("HRV", Display.number(r.hrvMs, unit: "ms"))
        }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        VStack(spacing: 9) {
            Text("Duration").font(.headline)
            metric("Total", Display.duration(r.totalSleepSeconds))
                .accessibilityLabel("Total sleep \(Display.duration(r.totalSleepSeconds))")
            metric("Deep", Display.duration(r.stages.deep.seconds))
            metric("REM", Display.duration(r.stages.rem.seconds))
            Divider()
            metric(r.timesArePresence ? "In bed" : "Bedtime", Display.time(r.bedtime, timezone: r.timezone))
            metric(r.timesArePresence ? "Out of bed" : "Wake time", Display.time(r.wakeTime, timezone: r.timezone))
        }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        if let fetched = ReportEnvelope.date(envelope.fetchedAt) {
            Text("Updated \(fetched, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
        }
        if r.score == nil || r.heartRateBpm == nil || r.hrvMs == nil
            || r.stages.deep.seconds == nil || r.stages.rem.seconds == nil {
            Text("— means unavailable from Eight Sleep.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.caption).accessibilityElement(children: .combine)
    }
    private func wakeDate(_ r: SleepReport) -> String {
        guard let date = ReportEnvelope.date(r.wakeTime) else { return r.date }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.timeZone = TimeZone(identifier: r.timezone)
        return formatter.string(from: date)
    }
}
