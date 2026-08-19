import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var store = StoreService.shared
    @State private var vault = VaultStore.shared
    @State private var notifications = NotificationService.shared
    @State private var navigator = AppNavigator.shared

    @State private var errorMessage: String?
    @State private var isShowingFeedback = false

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
                    LabeledContent("Birth certificate offices") {
                        Text(officeCoverage)
                    }
                    NavigationLink("Which office issues in each state") { StateOfficesView() }
                    NavigationLink("Every source we cite") { SourcesView() }
                } header: {
                    Text("Sources")
                } footer: {
                    Text("A rule set is only as fresh as its stalest page, so the date above is the oldest of them. Every state and DC links to that state's own vital records office, and the list says which of them somebody has read end to end and which have been checked against the office's own guidance without a full read. The five territories still link to the national directory, which has a picker: we would rather send you somewhere general and correct than somewhere specific and guessed.")
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

                Section {
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
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Only the two dates that are real doors closing get a notification: the job-based health plan and the Marketplace. A suggestion that fires at 9am is what teaches someone to switch the whole category off, and then they miss the one that mattered.")
                }

                Section {
                    LabeledContent("On this phone") {
                        Text(vaultSize)
                    }
                } header: {
                    Text("Document vault")
                } footer: {
                    Text("Photographs of your documents live in this app, unreadable while the phone is locked, and are excluded from every iCloud and computer backup. That is the trade: nothing can leak them, and nothing can restore them to a new phone either. The originals are still the record.")
                }

                Section("Plus") {
                    LabeledContent("Status") {
                        Text(store.isPro ? "Active" : "Free")
                    }
                    if !store.isPro {
                        Button("See what Plus adds") { navigator.requestUpgrade() }
                    }
                    if store.isPro {
                        Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
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

                Section {
                    Label {
                        Text("Baby Docs has no account. Everything you enter, and every photograph you add, stays on this phone unless you choose to send it: nothing is uploaded on its own, so there is nothing for us to delete on your behalf and nothing for anyone to breach. Sending a plan to the other parent puts your household answers and the baby's first name in that link, deliberately, and only when you tap it. Photographs never travel at all. If you buy Plus, Apple and RevenueCat hold the purchase itself; that record carries nothing about your family. The privacy policy sets out exactly what it contains.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Your data")
                }

                Section {
                    Button("Send feedback") { isShowingFeedback = true }
                } footer: {
                    Text("A rule that was wrong for your state or a link that went nowhere is worth more to us than a rating. This opens a mail draft and nothing else.")
                }

                Section {
                    Link("Privacy policy", destination: URL(string: "https://jackwallner.com/ios/babydocs/privacy-policy.html")!)
                    Link("Terms", destination: URL(string: "https://jackwallner.com/ios/babydocs/terms.html")!)
                    Link("Support", destination: URL(string: "https://jackwallner.com/ios/babydocs/support.html")!)
                } footer: {
                    Text("Version \(appVersion)")
                }
            }
            .listStyle(.insetGrouped)
            .planPageBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $isShowingFeedback) {
                FeedbackSheet()
            }
            .alert("Baby Docs", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var vaultSize: String {
        let bytes = vault.totalBytes()
        guard bytes > 0 else { return "Nothing yet" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "50 states and DC", not "CA".
    ///
    /// This row used to print the raw list of state codes, which for most of the
    /// app's life was the single word "CA". A parent in Ohio read that as either
    /// a bug or a boast, and either way it told them nothing about their own
    /// plan. The number is the honest summary, and the list behind it is where
    /// the detail lives.
    private var officeCoverage: String {
        let codes = StateVitalRecords.verifiedStateCodes
        let states = codes.filter { $0 != "DC" }.count
        guard states > 0 else { return "None yet" }
        return codes.contains("DC") ? "\(states) states and DC" : "\(states) states"
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
        await DeadlineReminderScheduler.reschedule(in: context)
    }
}

// MARK: - State offices

/// Which office issues a birth certificate, in every state.
///
/// Worth its own screen for the same reason `SourcesView` is: the app's claim is
/// that its links are checkable, and a claim nobody can inspect is not a
/// checkable one. It also shows the seam honestly. Eleven of these pages have
/// been read end to end; the rest have had their address and every sentence in
/// their note confirmed against the office's own published text. Flattening
/// those two into one green tick would be the easy thing and the wrong one.
struct StateOfficesView: View {
    @State private var query = ""

    private var offices: [VitalRecordsOffice] {
        let all = StateVitalRecords.allOffices
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            USState.displayName(for: $0.stateCode).localizedCaseInsensitiveContains(trimmed)
                || $0.stateCode.localizedCaseInsensitiveContains(trimmed)
                || $0.officeName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            ForEach(offices, id: \.stateCode) { office in
                Section {
                    if let url = office.url {
                        Link(destination: url) {
                            Label(office.officeName, systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                    }
                    if !office.orderingNote.isEmpty {
                        Text(office.orderingNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let checkedOn = office.verifiedOn {
                        Text(checkLine(office, checkedOn))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(USState.displayName(for: office.stateCode))
                }
            }

            Section {
                Text("The five territories are not in this list. Nobody has researched them, so the birth certificate task there links to the national directory and says so rather than sending you to an office we picked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listStyle(.insetGrouped)
        .planPageBackground()
        .searchable(text: $query, prompt: "Find a state")
        .navigationTitle("State offices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func checkLine(_ office: VitalRecordsOffice, _ date: Date) -> String {
        let day = date.formatted(.dateTime.month().day().year())
        return office.wasReadInFull
            ? "Page read end to end \(day)"
            : "Address and detail checked \(day). Not read end to end."
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
        .listStyle(.insetGrouped)
        .planPageBackground()
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
