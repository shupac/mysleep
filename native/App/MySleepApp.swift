import SwiftUI

@main
struct MySleepApp: App {
    @StateObject private var store = SleepStore()
    @ViewBuilder private var content: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") && ProcessInfo.processInfo.arguments.contains("--demo-controls") {
            NavigationStack { PodView() }
        } else { SleepView() }
        #else
        SleepView()
        #endif
    }
    var body: some Scene {
        WindowGroup { content.environmentObject(store).preferredColorScheme(.dark) }
    }
}
