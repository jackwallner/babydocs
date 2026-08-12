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
                    LabeledContent("Oldest source check") {
                        Text(RequirementCatalog.reviewedOn, format: .dateTime.month().day().year())
                    }
                    LabeledContent("States with verified detail") {
                        Text(verifiedStates)
                    }
                    NavigationLink("Every source we cite") { SourcesView() }
                } header: {
                    Text("Sources")
                } footer: {
                    Text("A rule set is only as fresh as its stalest page, so the date above is the oldest of them. States without verified detail link to the national directory instead. We would rather send you somewhere general and correct than somewhere specific and guessed, and where there is nothing honest to cite the task says so.")
                }

                if let recovered = BabyModelStore.recoveredStoreURL {
                    Section {
                        Label("The saved plan could not be opened", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Baby Docs started with an empty plan because the file it saves to could not be read. Nothing was deleted: the old file is still on this phone at \(recovered.lastPathComponent). Get in touch through Support before setting everything up again, and it may be recoverable.")
                            .font(.footnote)
                    } header: {
                        Text("Storage")
                    }
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
                            do {
                                switch try await store.restore() {
                                case .restored:
                                    errorMessage = "Plus is active on this device again."
                                case .nothingToRestore:
                                    errorMessage = "No previous purchase was found for this Apple Account. If you bought Plus with a different account, sign in with that one and try again."
                                case .unavailable:
                                    errorMessage = "Purchases cannot be restored in this build."
                                }
                            } catch {
                                errorMessage = error.localizedDescription
                            }
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
            .alert("Baby Docs", isPresented: errorBinding) {
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

// MARK: - Sources

/// Every page the catalog cites, with its date and its limits.
///
/// Worth a screen of its own rather than a single "reviewed on" line: the claim
/// this app makes is that its dates are checkable, and a list nobody can see is
/// not a checkable claim. It also shows the two rules that cite nothing, which is
/// the part a competitor would hide.
struct SourcesView: View {
    private var sorted: [SourceEntry] {
        SourceManifest.all.sorted { $0.reviewedOn < $1.reviewedOn }
    }

    private var uncited: [RequirementRule] {
        RequirementCatalog.all.filter { !$0.noSourceReason.isEmpty }
    }

    var body: some View {
        List {
            ForEach(sorted) { entry in
                Section {
                    if let url = entry.url {
                        Link(destination: url) {
                            Label(entry.title, systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                    }
                    Text(entry.agency)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent(statusLabel(entry.status)) {
                        Text(entry.reviewedOn, format: .dateTime.month().day().year())
                    }
                    .font(.caption)
                    if !entry.limitations.isEmpty {
                        Text(entry.limitations)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !uncited.isEmpty {
                Section {
                    ForEach(uncited) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.title).font(.subheadline)
                            Text(rule.noSourceReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text("Cites nothing, on purpose")
                } footer: {
                    Text("These tasks are on the list because they matter, not because a government page says to do them. Rather than link a plausible-looking page that does not support the advice, they say where the answer actually comes from.")
                }
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusLabel(_ status: SourceStatus) -> String {
        switch status {
        case .verified: return "Read on"
        case .federalFallback: return "Federal page, read on"
        case .awaitingReview: return "Added on, not yet read"
        }
    }
}
