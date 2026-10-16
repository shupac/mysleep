import SwiftUI

struct PodView: View {
    @StateObject private var store = PodStore()
    @Environment(\.scenePhase) private var phase
    @State private var confirmEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(spacing: 12) {
                    if store.isWorking { ProgressView("Contacting Pod…") }
                    if let status = store.status {
                        Label(status.isOff ? "Off" : "Mode: \(status.currentState.type.capitalized)",
                              systemImage: status.isOff ? "power" : "moon.fill")
                            .font(.headline)
                    } else if !store.isWorking {
                        Text("Live status unavailable").font(.headline).multilineTextAlignment(.center)
                    }
                    VStack(spacing: 8) {
                        Text("\(Int(store.selectedFahrenheit))°F").font(.system(size: 38, weight: .semibold, design: .rounded))
                            .foregroundStyle(.blue).monospacedDigit()
                        Slider(value: $store.selectedFahrenheit, in: PodTemperature.range, step: 1)
                            .accessibilityLabel("Temperature in Fahrenheit")
                            .accessibilityValue("\(Int(store.selectedFahrenheit)) degrees Fahrenheit")
                            .accessibilityIdentifier("temperatureFahrenheit")
                            .disabled(!store.canControl(at: context.date))
                        HStack { Text("Cooler"); Spacer(); Text("Warmer") }.font(.caption2).foregroundStyle(.secondary)
                        Button("Apply temperature") { Task { await store.applyTemperature() } }
                            .accessibilityIdentifier("applyTemperature")
                            .disabled(!store.canControl(at: context.date))
                        if let status = store.status, let fahrenheit = PodTemperature.fahrenheit(level: status.currentLevel) {
                            Text("Your profile · Setting \(fahrenheit)°F")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Controls follow your saved Eight Sleep profile’s bed assignment.")
                            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Text("Applying this temperature turns heating/cooling on.")
                            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    if store.status?.isOff == true {
                        Button("Turn on", systemImage: "power") { Task { await store.send(.turnOn) } }
                            .accessibilityIdentifier("turnOnPod").disabled(!store.canControl(at: context.date))
                    }
                    Button("End sleep", systemImage: "stop.circle", role: .destructive) { confirmEnd = true }
                        .accessibilityIdentifier("endSleep").disabled(!store.canControl(at: context.date))
                    if let message = store.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
                    if let error = store.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                    if let checked = store.checkedAt {
                        Text("Checked \(checked, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("Refresh status", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                        .disabled(store.isWorking)
                    Text("End sleep stops your active sleep session and requests a fresh report. Processing may take a moment.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 8).padding(.bottom)
                    .frame(maxWidth: 430).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Pod controls")
        .task { await store.refresh() }
        .onChange(of: phase) { _, value in if value == .active { Task { await store.refresh() } } }
        .confirmationDialog("End sleep?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End sleep and process report", role: .destructive) { Task { await store.send(.endSleep) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This stops the most recent active sleep session for your saved Eight Sleep profile.")
        }
    }
}
