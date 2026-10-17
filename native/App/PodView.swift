import SwiftUI

/// Inline home-screen controls, shown only while the Pod is on or updating.
struct PodView: View {
    @EnvironmentObject private var store: PodStore
    let state: PodControlState
    let endSleep: () async -> Void
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: 12) {
            switch state {
            case .on:
                if let status = store.status, let fahrenheit = PodTemperature.fahrenheit(level: status.currentLevel),
                   Int(store.selectedFahrenheit) != fahrenheit {
                    Text("Current · \(fahrenheit)°F").font(.caption).foregroundStyle(.secondary)
                }
                temperatureEditor
                Button("End sleep", systemImage: "stop.circle", role: .destructive) { confirmEnd = true }
                    .accessibilityIdentifier("endSleep")
            case .changing(let action):
                ProgressView(action == .endSleep ? "Ending sleep…" : "Applying temperature…")
            case .confirming:
                Label("Awaiting confirmation", systemImage: "clock").font(.headline)
            case .refreshRequired:
                Label("Refresh required", systemImage: "arrow.clockwise").font(.headline)
            case .loading:
                ProgressView("Checking…")
            case .off, .unavailable, .unsupported:
                EmptyView()
            }
            #if DEBUG
            if let message = store.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            #endif
        }
        .confirmationDialog("End sleep?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End sleep and turn off bed", role: .destructive) { Task { await endSleep() } }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var temperatureEditor: some View {
        VStack(spacing: 8) {
            Text("\(Int(store.selectedFahrenheit))°F").font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(.blue).monospacedDigit()
            Slider(value: $store.selectedFahrenheit, in: PodTemperature.range, step: 1)
                .accessibilityLabel("Temperature in Fahrenheit")
                .accessibilityValue("\(Int(store.selectedFahrenheit)) degrees Fahrenheit")
                .accessibilityIdentifier("temperatureFahrenheit")
            Button("Apply temperature") { Task { await store.applyTemperature() } }
                .accessibilityIdentifier("applyTemperature")
        }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
