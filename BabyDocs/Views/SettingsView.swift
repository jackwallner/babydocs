import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var auth = AuthService.shared
    @State private var family = FamilyService.shared
    @State private var store = StoreService.shared
    @State private var notifications = NotificationService.shared
    @State private var navigator = AppNavigator.shared

    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(PlanExporter.disclaimer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("What this app is")
                }

                Section {
                    LabeledContent("Rules last reviewed") {
                        Text(RequirementCatalog.reviewedOn, format: .dateTime.month().day().year())
                    }
                    LabeledContent("States with verified detail") {
                        Text(verifiedStates)
                    }
                } header: {
                    Text("Sources")
                } footer: {
                    Text("Every task links to the government page its rule came from. States without verified detail link to the federal directory instead, which carries a state picker. We would rather send you somewhere general and correct than somewhere specific and guessed.")
                }

                Section("Reminders") {
                    LabeledContent("Notifications") {
                        Text(notificationStatus)
                    }
                    if notifications.authorizationStatus == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else if notifications.authorizationStatus == .notDetermined {
                        Button("Turn on deadline reminders") {
                            Task {
                                await notifications.requestAuthorization()
                                await rescheduleReminders()
                            }
                        }
                    }
                    if notifications.remoteRegistrationFailed {
                        Text("This device could not register for notifications. Reminders scheduled on the phone still work.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Plus") {
                    LabeledContent("Status") {
                        Text(store.isPro || family.hasPlus ? "Active" : "Free")
                    }
                    if !(store.isPro || family.hasPlus) {
                        Button("See what Plus adds") { navigator.requestUpgrade() }
                    }
                    Button("Restore purchases") {
                        Task {
                            do { try await store.restore() } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }

                if auth.isSignedIn {
                    Section("Account") {
                        LabeledContent("Signed in as") {
                            Text(auth.displayName.isEmpty ? "Apple ID" : auth.displayName)
                        }
                        Button("Sign out") { Task { await auth.signOut() } }
                        Button("Delete account", role: .destructive) { isConfirmingDelete = true }
                    }
                }

                Section {
                    Link("Privacy policy", destination: URL(string: "https://jackwallner.com/ios/babydocs/privacy-policy.html")!)
                    Link("Terms", destination: URL(string: "https://jackwallner.com/ios/babydocs/terms.html")!)
                    Link("Support", destination: URL(string: "https://jackwallner.com/ios/babydocs/support.html")!)
                } footer: {
                    Text("Version \(appVersion)")
                }
            }
            .navigationTitle("Settings")
            .alert("Delete your account?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive) {
                    Task {
                        do { try await auth.deleteAccount() } catch { errorMessage = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes your account and your membership. The plan on this phone stays where it is.")
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var verifiedStates: String {
        let codes = StateVitalRecords.verifiedStateCodes
        return codes.isEmpty ? "None yet" : codes.joined(separator: ", ")
    }

    private var notificationStatus: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional: return "On"
        case .denied: return "Off"
        default: return "Not asked"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func rescheduleReminders() async {
        let tasks = ((try? context.fetch(FetchDescriptor<Child>())) ?? []).flatMap(\.liveTasks)
        await DeadlineReminderScheduler.reschedule(for: tasks)
    }
}
