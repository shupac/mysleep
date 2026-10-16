import SwiftUI

@MainActor
final class PodStore: ObservableObject {
    @Published private(set) var status: PodStatus?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var isWorking = false
    @Published private(set) var error: String?
    @Published private(set) var message: String?
    @Published var selectedFahrenheit: Double = 80
    private let service: SleepService
    private let demo: Bool

    init(service: SleepService = .shared) {
        self.service = service
        #if DEBUG
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        demo = false
        #endif
    }
    func canControl(at now: Date = Date()) -> Bool {
        guard !isWorking, status != nil, let checkedAt else { return false }
        return now.timeIntervalSince(checkedAt) < 60
    }
    func refresh() async {
        guard !isWorking else { return }
        isWorking = true; error = nil
        defer { isWorking = false }
        do {
            let fresh = demo ? status ?? PodStatus(currentLevel: -20, currentState: .init(type: "smart"))
                : try await service.podStatus()
            update(fresh)
        } catch {
            status = nil; checkedAt = nil
            self.error = error.localizedDescription
        }
    }
    func applyTemperature() async {
        do { await send(.temperature(try PodTemperature.level(fahrenheit: selectedFahrenheit))) }
        catch { self.error = error.localizedDescription }
    }
    func send(_ action: PodAction) async {
        guard canControl() else {
            error = "Refresh live Pod status before sending a command."
            return
        }
        isWorking = true; error = nil; message = nil
        let previous = status
        status = nil; checkedAt = nil
        defer { isWorking = false }
        do {
            if demo {
                switch action {
                case .temperature(let level): update(PodStatus(currentLevel: level, currentState: .init(type: "smart")))
                case .turnOn: update(PodStatus(currentLevel: previous?.currentLevel ?? 0, currentState: .init(type: "smart")))
                case .endSleep: if let previous { update(previous) }
                case .turnOff: update(PodStatus(currentLevel: previous?.currentLevel ?? 0, currentState: .init(type: "off")))
                }
                message = "Demo only. No Pod command was sent."
            } else {
                try await service.control(action)
                message = action == .endSleep ? "Sleep session ended. Refresh your sleep report; processing may take a moment." : "Command accepted. Cloud status may take a moment to update."
                do { update(try await service.podStatus()) }
                catch { self.error = "Command accepted, but status couldn’t be refreshed. Tap Refresh status." }
            }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func update(_ fresh: PodStatus) {
        guard let fahrenheit = PodTemperature.fahrenheit(level: fresh.currentLevel) else {
            status = nil; checkedAt = nil; error = SleepError.invalidResponse.localizedDescription
            return
        }
        status = fresh; checkedAt = Date()
        selectedFahrenheit = min(PodTemperature.range.upperBound, max(PodTemperature.range.lowerBound, Double(fahrenheit)))
    }
}
