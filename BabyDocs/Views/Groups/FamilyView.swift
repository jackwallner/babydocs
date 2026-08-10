import SwiftData
import SwiftUI

/// Who else is on this plan.
///
/// The framing throughout is "both of you", not "invite a collaborator". The
/// realistic second user is the other parent, and the realistic failure this
/// screen prevents is the two of them each independently phoning the same office
/// about the same certificate.
struct FamilyView: View {
    @Environment(\.modelContext) private var context
    @State private var auth = AuthService.shared
    @State private var family = FamilyService.shared
    @State private var store = StoreService.shared
    @State private var sync = SyncCoordinator.shared
    @State private var navigator = AppNavigator.shared

    @State private var isSigningIn = false
    @State private var isInviting = false
    @State private var isJoining = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !SupabaseConfig.isConfigured {
                    Section {
                        EmptyStateView(
                            symbol: "person.2.slash",
                            title: "Sharing is not switched on yet",
                            message: "Everything else in the app works on this device. When sharing ships, the plan you have already built moves across as it is."
                        )
                        .listRowBackground(Color.clear)
                    }
                } else if !auth.isSignedIn {
                    signedOutSection
                } else if family.activeGroupID == nil {
                    noFamilySection
                } else {
                    membersSection
                    invitesSection
                    syncSection
                    dangerSection
                }
            }
            .navigationTitle("Family")
            .task {
                await family.loadMembers()
                await family.loadPendingInvites()
            }
            .sheet(isPresented: $isSigningIn) { SignInView() }
            .sheet(isPresented: $isInviting) { InviteSheet() }
            .sheet(isPresented: $isJoining) { JoinFamilyView() }
            .onChange(of: navigator.pendingInviteCode) { _, code in
                if code != nil { isJoining = true }
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var signedOutSection: some View {
        Section {
            EmptyStateView(
                symbol: "person.2.fill",
                title: "Work from one plan",
                message: "Sign in to share the plan with the other parent. Ticking a document off on one phone shows on the other, and nobody rings the same office twice.",
                actionTitle: "Sign in",
                action: { isSigningIn = true }
            )
            .listRowBackground(Color.clear)

            Button("I have an invitation") { isJoining = true }
        }
    }

    private var noFamilySection: some View {
        Section {
            Button {
                createFamily()
            } label: {
                Label("Start a shared family", systemImage: "plus.circle")
            }
            .disabled(isCreating)

            Button("I have an invitation") { isJoining = true }
        } footer: {
            Text("Starting a family uploads the plan already on this phone. Nothing is sent anywhere until you do.")
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(family.members) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.resolvedName)
                        Text(member.role.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if family.role == .owner && !member.isSelf {
                        Menu {
                            ForEach(GroupRole.allCases.filter { $0 != .owner }, id: \.self) { role in
                                Button(role.label) { changeRole(of: member.id, to: role) }
                            }
                            Divider()
                            Button("Remove", role: .destructive) { removeMember(member.id) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        } header: {
            Text(family.familyName.isEmpty ? "Members" : family.familyName)
        } footer: {
            Text(GroupRole.parent.blurb)
        }
    }

    private var invitesSection: some View {
        Section {
            if family.role.isStaff {
                Button {
                    if store.isPro || family.hasPlus {
                        isInviting = true
                    } else {
                        navigator.requestUpgrade()
                    }
                } label: {
                    Label("Invite the other parent", systemImage: "envelope")
                }
            }

            ForEach(family.pendingInvites) { invite in
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.code).font(.body.monospaced())
                    Text(invite.isExpired
                         ? "Expired"
                         : "Expires \(invite.expiresAt, format: .dateTime.month().day().hour().minute())")
                        .font(.caption)
                        .foregroundStyle(invite.isExpired ? .red : .secondary)
                }
                .swipeActions {
                    Button("Revoke", role: .destructive) { revoke(invite.code) }
                }
            }
        } header: {
            Text("Invitations")
        } footer: {
            Text("An invitation works once and expires after 48 hours. Whoever joins is never charged: one purchase covers the family.")
        }
    }

    private var syncSection: some View {
        Section {
            LabeledContent("Last synced") {
                if let date = sync.lastSyncedAt {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Not yet")
                }
            }
            if sync.isOffline {
                Label("Offline. Showing your saved copy.", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = sync.lastError, !sync.isOffline {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if sync.conflictCount > 0 {
                Text("\(sync.conflictCount) changes need a look. Someone edited the same thing while you were offline.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button("Sync now") { Task { await sync.syncNow() } }
        } header: {
            Text("Sync")
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Leave this family", role: .destructive) {
                run { try await family.leaveFamily() }
            }
            if family.role == .owner {
                Button("Delete this family", role: .destructive) {
                    run { try await family.deleteFamily() }
                }
            }
        } footer: {
            Text("Leaving removes the shared plan from this phone. It does not delete the other parent's copy.")
        }
    }

    // MARK: - Actions

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func createFamily() {
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let name = auth.displayName.isEmpty ? "Our family" : "\(auth.displayName)'s family"
                let id = try await family.createFamily(named: name)
                await SyncCoordinator.shared.adoptLocalData(into: id)
                await family.loadMembers()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func changeRole(of userID: UUID, to role: GroupRole) {
        run { try await family.changeRole(of: userID, to: role) }
    }

    private func removeMember(_ userID: UUID) {
        run { try await family.removeMember(userID) }
    }

    private func revoke(_ code: String) {
        run { try await family.revokeInviteCode(code) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { errorMessage = error.localizedDescription }
        }
    }
}
