import AppIntents

struct GetLatestSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Latest Sleep Report"
    static var description = IntentDescription("Fetch your latest completed Eight Sleep report and read a concise summary.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text: String
        do { text = SleepSummary.text(try await SleepService.shared.latest()) }
        catch { text = (error as? SleepError)?.localizedDescription ?? "Your sleep report is temporarily unavailable." }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}
struct EndSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "End Sleep"
    static var description = IntentDescription("Turn off your bed’s heating and cooling, stop any active Eight Sleep session, and start processing your sleep report.")
    static var openAppWhenRun = false
    // HomePod Personal Requests authorizes the caller; this action may run on a locked iPhone.
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SleepService.shared.control(.endSleep)
        return .result(dialog: "Sleep ended.")
    }
}
struct SleepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: EndSleepIntent(), phrases: [
            "Done sleeping with \(.applicationName)",
            "End with \(.applicationName)",
            "End sleep with \(.applicationName)",
            "End sleep in \(.applicationName)"
        ], shortTitle: "Done sleeping", systemImageName: "stop.circle")
        AppShortcut(intent: GetLatestSleepIntent(), phrases: [
            "How did I sleep with \(.applicationName)",
            "Get my sleep report from \(.applicationName)"
        ], shortTitle: "How did I sleep?", systemImageName: "moon.zzz.fill")
    }
}
