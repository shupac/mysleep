import Foundation

struct PodStatus: Decodable, Equatable {
    struct State: Decodable, Equatable { let type: String }
    let currentLevel: Int
    let currentState: State
    var isOff: Bool { currentState.type == "off" }
    // Active schedules report phase-qualified modes, e.g. smart:bedtime.
    var isOn: Bool {
        currentState.type == "smart" || (currentState.type.hasPrefix("smart:") && currentState.type.count > 6)
    }
}
enum PodAction: Equatable {
    case temperature(Int)
    case turnOff
    case turnOn
    case endSleep
}

/// Fahrenheit setpoints use pyEight's nonlinear lookup, not a linear scale.
/// Source: lukas-clarke/eight_sleep, pyEight/constants.py (MIT).
/// See docs/provenance.md and docs/pyeight-LICENSE.txt.
enum PodTemperature {
    static let range: ClosedRange<Double> = 55...110
    private static let lookup: [(level: Int, fahrenheit: Int)] = [
        (-100,55), (-99,56), (-97,57), (-95,58), (-94,59), (-92,60),
        (-90,61), (-86,62), (-81,63), (-77,64), (-72,65), (-68,66),
        (-63,67), (-58,68), (-54,69), (-49,70), (-44,71), (-40,72),
        (-35,73), (-31,74), (-26,75), (-21,76), (-18,77), (-17,77),
        (-12,78), (-7,79), (-3,80), (1,81), (4,82), (7,83), (10,84),
        (14,85), (16,86), (17,86), (20,87), (23,88), (26,89), (29,90),
        (32,91), (35,92), (38,93), (41,94), (44,95), (48,96), (51,97),
        (54,98), (57,99), (60,100), (63,101), (66,102), (69,103),
        (72,104), (75,105), (78,106), (80,107), (81,107), (85,108),
        (88,109), (92,110), (100,111),
    ]
    static func level(fahrenheit: Double) throws -> Int {
        guard fahrenheit.isFinite, range.contains(fahrenheit), fahrenheit.rounded() == fahrenheit,
              let entry = lookup.first(where: { $0.fahrenheit == Int(fahrenheit) }) else {
            throw SleepError.invalidFahrenheit
        }
        return entry.level
    }
    static func fahrenheit(level: Int) -> Int? {
        guard (-100...100).contains(level) else { return nil }
        return lookup.min {
            (abs($0.level - level), $0.level) < (abs($1.level - level), $1.level)
        }?.fahrenheit
    }
}

/// Shared screen policy: power, freshness, and command progress decide all controls.
enum PodControlActivity: Equatable {
    case idle, refreshing
    case sending(PodAction)
    case confirming(PodAction)
}

enum PodControlState: Equatable {
    case loading, off, on, refreshRequired, unavailable
    case changing(PodAction), confirming(PodAction)
    case unsupported(String)

    init(status: PodStatus?, checkedAt: Date?, activity: PodControlActivity, now: Date) {
        switch activity {
        case .refreshing: self = .loading; return
        case .sending(let action): self = .changing(action); return
        case .confirming(let action): self = .confirming(action); return
        case .idle: break
        }
        guard let status, let checkedAt else { self = .unavailable; return }
        guard now.timeIntervalSince(checkedAt) < 60 else { self = .refreshRequired; return }
        if status.isOff { self = .off }
        else if status.isOn { self = .on }
        else { self = .unsupported(status.currentState.type) }
    }

    func allows(_ action: PodAction) -> Bool {
        switch (self, action) {
        case (.on, .temperature), (.on, .endSleep): true
        default: false
        }
    }
}

extension PodAction {
    func isConfirmed(by status: PodStatus) -> Bool {
        switch self {
        case .turnOff, .endSleep: status.isOff
        case .turnOn: status.isOn
        case .temperature(let level): status.isOn && status.currentLevel == level
        }
    }
}
