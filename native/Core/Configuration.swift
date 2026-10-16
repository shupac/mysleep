import Foundation

struct Credentials: Codable, Equatable {
    let email: String
    let password: String
    let timezone: String

    init(email: String, password: String, timezone: String) throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), !password.isEmpty, TimeZone(identifier: timezone) != nil else {
            throw SleepError.invalidConfiguration
        }
        self.email = email
        self.password = password
        self.timezone = timezone
    }
}
struct AccessToken: Codable, Equatable {
    let value: String
    let expiresAt: Date
    var userID: String?
}
struct SavedSession: Codable {
    let credentials: Credentials
    var token: AccessToken?
}
enum SleepError: Error, LocalizedError, Equatable {
    case notConfigured, invalidConfiguration, authentication, rateLimited, unavailable, invalidResponse, noCompletedReport, secureStorage
    case noActiveSleep
    case invalidFahrenheit, invalidTemperature, controlsBusy, partialTemperatureChange, controlUnconfirmed
    var errorDescription: String? {
        switch self {
        case .invalidFahrenheit: "Choose a whole-degree temperature from 55°F to 110°F."
        case .invalidTemperature: "Temperature level must be between −100 and 100."
        case .controlsBusy: "Another Pod request is in progress. Please wait."
        case .noActiveSleep: "No recent active sleep session was found. Refresh your sleep report."
        case .partialTemperatureChange: "Heating/cooling may be on, but the temperature change wasn’t confirmed. Refresh status before retrying."
        case .controlUnconfirmed: "The Pod request wasn’t confirmed and may have taken effect. Refresh status before retrying."
        case .notConfigured: "Sign in to Eight Sleep in the app on this device first."
        case .invalidConfiguration: "Enter your Eight Sleep email, password, and a valid IANA time zone."
        case .authentication: "Eight Sleep rejected sign-in. Check your credentials in Settings."
        case .rateLimited: "Eight Sleep is limiting requests. Please try again in a minute."
        case .unavailable: "Couldn’t reach Eight Sleep. Check your connection and try again."
        case .invalidResponse: "Eight Sleep returned an unsupported response."
        case .noCompletedReport: "No completed sleep report is available in the last two weeks."
        case .secureStorage: "Couldn’t access secure storage. Unlock this device and try again."
        }
    }
}
