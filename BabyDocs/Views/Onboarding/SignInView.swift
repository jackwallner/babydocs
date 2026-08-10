import AuthenticationServices
import SwiftUI

/// Sign in with Apple, and nothing else.
///
/// Not because email is unfinished, but because an app whose entire pitch is
/// "we keep the sensitive paperwork straight" cannot open with a form asking for
/// an address and a password. Apple's flow is one tap, hides the address by
/// default, and is what a reviewer expects to see next to the account deletion
/// this app also has to offer.
struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthService.shared
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "person.2.badge.key")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("One plan, both parents")
                        .font(.title2.weight(.bold))
                    Text("An account exists for one reason: so the other parent sees the same list. Everything you have entered stays on this phone either way.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)

                Spacer()

                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        handle(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .disabled(isWorking)

                    Text("Baby Docs stores your name and the plan you build. It never asks for a Social Security number, and the one-page summary never prints one.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .alert("Could not sign in", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // A user-cancelled sheet is not a failure worth an alert.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    try await auth.completeAppleSignIn(authorization)
                    await StoreService.shared.identify()
                    await FamilyService.shared.refresh()
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
