import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SleepStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var error: String?
    @State private var saving = false
    @State private var confirmSignOut = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Eight Sleep account") {
                    TextField("Email", text: $email)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("email")
                    SecureField("Password", text: $password)
                        .textContentType(.password).accessibilityIdentifier("password")
                    TextField("Time zone", text: $timezone)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Credentials stay in this device’s Keychain. Sign in separately on your Watch for independent access.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.orange).font(.caption) }
                Button(saving ? "Saving…" : "Save and connect") {
                    saving = true
                    Task {
                        do {
                            try await store.save(email: email, password: password, timezone: timezone)
                            password = ""; dismiss()
                        } catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }.disabled(saving || password.isEmpty)
                if store.isConfigured {
                    Section {
                        Button("Sign out on this device", role: .destructive) { confirmSignOut = true }
                            .disabled(saving)
                    }
                }
            }.navigationTitle("Settings")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving) } }
                .onAppear { email = store.email; timezone = store.timezone }
                .confirmationDialog("Remove this device’s credentials and saved report?", isPresented: $confirmSignOut) {
                    Button("Sign out", role: .destructive) {
                        saving = true
                        Task {
                            do { try await store.disconnect(); dismiss() }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }
                }
        }
    }
}