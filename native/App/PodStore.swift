import SwiftUI

@MainActor
final class PodStore: ObservableObject {
    @Published private(set) var status: PodStatus?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var activity: PodControlActivity = .idle
    @Published private(set) var error: String?
    @Published private(set) var message: String?
    @Published private(set) var didEndSleep = false
    @Published var selectedFahrenheit: Double = 80
    private var pendingConfirmation: PodAction?
    private let service: SleepService
    private let demo: Bool
    private let demoOff: Bool

    init(service: SleepService = .shared) {
        self.service = service
        #if DEBUG
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        demoOff = !ProcessInfo.processInfo.arguments.contains("--demo-pod-on")
        #else
        demo = false; demoOff = false
        #endif
    }
    var isWorking: Bool {
        switch activity {
        case .refreshing, .sending: true
        default: false
        }
    }
    func state(at now: Date = Date()) -> PodControlState {
        PodControlState(status: status, checkedAt: checkedAt, activity: activity, now: now)
    }
    func clear() {
        status = nil; checkedAt = nil; pendingConfirmation = nil
        activity = .idle; error = nil; message = nil; didEndSleep = false
    }
    func refresh() async {
        guard !isWorking else { return }
        if didEndSleep, pendingConfirmation == .endSleep { pendingConfirmation = nil }
        activity = .refreshing; error = nil
        do {
            let fresh = demo ? status ?? PodStatus(currentLevel: -20, currentState: .init(type: demoOff ? "off" : "smart:bedtime"))
                : try await service.podStatus()
            update(fresh)
        } catch {
            status = nil; checkedAt = nil
            activity = pendingConfirmation.map { .confirming($0) } ?? .idle
            self.error = error.localizedDescription
        }
    }
    func applyTemperature() async {
        do { await send(.temperature(try PodTemperature.level(fahrenheit: selectedFahrenheit))) }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func send(_ action: PodAction) async -> Bool {
        // Recheck on dispatch, including after a confirmation dialog has been open.
        guard state().allows(action) else {
            error = "Refresh to check Pod status."
            return false
        }
        activity = .sending(action); error = nil; message = nil
        let previous = status
        status = nil; checkedAt = nil
        do {
            if demo {
                pendingConfirmation = action
                let level: Int
                if case .temperature(let selected) = action { level = selected }
                else { level = previous?.currentLevel ?? 0 }
                let type = action == .endSleep || action == .turnOff ? "off" : "smart"
                update(PodStatus(currentLevel: level, currentState: .init(type: type)))
                if action == .endSleep { didEndSleep = true }
                message = "Demo only. No Pod command was sent."
            } else {
                try await service.control(action)
                pendingConfirmation = action
                if action == .endSleep { didEndSleep = true }
                activity = .confirming(action)
                message = action == .endSleep ? "Sleep ended." : nil
                do { update(try await service.podStatus()) }
                catch { self.error = "Command accepted. Refresh to check status." }
            }
            return true
        } catch is CancellationError {
            activity = .idle
            return false
        } catch {
            activity = .idle
            self.error = error.localizedDescription
            return false
        }
    }
    private func update(_ fresh: PodStatus) {
        guard let fahrenheit = PodTemperature.fahrenheit(level: fresh.currentLevel) else {
            status = nil; checkedAt = nil
            activity = pendingConfirmation.map { .confirming($0) } ?? .idle
            error = SleepError.invalidResponse.localizedDescription
            return
        }
        status = fresh; checkedAt = Date()
        selectedFahrenheit = min(PodTemperature.range.upperBound, max(PodTemperature.range.lowerBound, Double(fahrenheit)))
        if let pendingConfirmation, pendingConfirmation.isConfirmed(by: fresh) { self.pendingConfirmation = nil }
        if fresh.isOn, pendingConfirmation == nil { didEndSleep = false }
        activity = pendingConfirmation.map { .confirming($0) } ?? .idle
    }
}
