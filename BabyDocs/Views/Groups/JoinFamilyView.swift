import SwiftUI

/// Redeeming an invitation.
///
/// The code arrives three ways (a tap on the web link, a paste, or read out
/// loud), and all three land here. `InviteLink.normalized` is what makes the
/// dictated case work: a code typed as "h7k-2m 9qb" is the same code.
struct JoinFamilyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthService.shared
    @State private var family = FamilyService.shared
    @State private var navigator = AppNavigator.shared

    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invitation code", text: $code)
                        .font(.system(.title3, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Enter the code")
                } footer: {
                    Text("Eight characters. Spaces and dashes are ignored, and it does not matter whether you type it in capitals.")
                }

                if !auth.isSignedIn {
                    Section {
                        Button("Sign in first") { isSigningIn = true }
                    } footer: {
                        Text("Joining a family needs an account, so the other parent's plan knows who you are.")
                    }
                }

                Section {
                    Button {
                        join()
                    } label: {
                        Text("Join").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || !auth.isSignedIn || InviteLink.normalized(code) == nil)
                }
            }
            .navigationTitle("Join a family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish() }
                }
            }
            .sheet(isPresented: $isSigningIn) { SignInView() }
            .onAppear {
                if let pending = navigator.pendingInviteCode { code = pending }
            }
            .alert("Could not join", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func join() {
        guard let normalized = InviteLink.normalized(code) else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await family.acceptInvite(code: normalized)
                await family.loadMembers()
                await SyncCoordinator.shared.syncNow()
                finish()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Clears the pending code on the way out, whether or not it worked. A code
    /// left in place re-presents this sheet on the next launch, over and over,
    /// for someone who has already decided not to use it.
    private func finish() {
        navigator.pendingInviteCode = nil
        dismiss()
    }
}
