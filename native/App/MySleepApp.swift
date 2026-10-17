import SwiftUI
import AppIntents

@main
struct MySleepApp: App {
    @StateObject private var store = SleepStore()
    @StateObject private var pod = PodStore()
    init() { SleepShortcuts.updateAppShortcutParameters() }
    var body: some Scene {
        WindowGroup { SleepView().environmentObject(store).environmentObject(pod).preferredColorScheme(.dark) }
    }
}
