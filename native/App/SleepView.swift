import SwiftUI

struct SleepView: View {
    @EnvironmentObject private var store: SleepStore
    @EnvironmentObject private var pod: PodStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var checkingBed = true
    @State private var endingSleep = false
    private let accent = Color(red: 0.52, green: 0.76, blue: 1)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if checkingBed {
                        ProgressView("Checking…")
                    } else if endingSleep {
                        ProgressView(store.isLoading ? "Getting your sleep…" : "Ending sleep…")
                    } else if store.isConfigured {
                        TimelineView(.periodic(from: .now, by: 5)) { context in
                            let state = pod.state(at: context.date)
                            if showsReport(state) {
                                switch state {
                                case .unavailable, .unsupported:
                                    Text("Bed status unavailable").font(.caption2).foregroundStyle(.secondary)
                                default: EmptyView()
                                }
                                reportContent
                            } else {
                                PodView(state: state) {
                                    endingSleep = true
                                    defer { endingSleep = false }
                                    if await pod.send(.endSleep) { await store.refresh(force: true) }
                                }
                            }
                        }
                    } else {
                        Image(systemName: "moon.zzz.fill").font(.largeTitle).foregroundStyle(accent)
                        Text("Your sleep, at a glance").font(.headline)
                        Text("Sign in to Eight Sleep in Settings.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let error = pod.error, store.isConfigured {
                        Text(error).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    #if os(watchOS)
                    if store.isConfigured {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh(force: true) } }
                            .disabled(store.isLoading || pod.isWorking || endingSleep)
                    }
                    #endif
                    Button("Settings", systemImage: "gearshape") { showSettings = true }.disabled(store.isLoading || pod.isWorking || endingSleep)
                        .font(.caption)
                }.padding(.horizontal, 8).padding(.bottom)
                .frame(maxWidth: 430).frame(maxWidth: .infinity)
            }
            .navigationTitle("MySleep")
            #if os(iOS)
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable { await refresh(force: true) }
            #endif
            .task { await start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await start() } }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await refresh() } }) {
                SettingsView().environmentObject(store)
            }
        }
    }
    private func start() async {
        guard !endingSleep, !pod.isWorking else { return }
        checkingBed = true
        defer { checkingBed = false }
        await store.start(loadReport: false)
        if store.isConfigured {
            await pod.refresh()
            checkingBed = false
            if showsReport(pod.state()) { await store.refresh() }
        } else { pod.clear() }
    }
    private func refresh(force: Bool = false) async {
        guard !endingSleep, !pod.isWorking, !store.isLoading else { return }
        if store.isConfigured {
            await pod.refresh()
            if showsReport(pod.state()) { await store.refresh(force: force) }
        } else { pod.clear() }
    }
    private func showsReport(_ state: PodControlState) -> Bool {
        if pod.didEndSleep { return true }
        switch state {
        case .off, .unavailable, .unsupported: return true
        case .refreshRequired: return pod.status?.isOff == true
        default: return false
        }
    }
    @ViewBuilder
    private var reportContent: some View {
        if store.isLoading {
            ProgressView("Getting your sleep…").padding(.vertical, 30)
        } else if let envelope = store.report {
            reportView(envelope)
        } else {
            Text("No report yet").font(.headline)
        }
        if let error = store.error {
            Text(error).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
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
