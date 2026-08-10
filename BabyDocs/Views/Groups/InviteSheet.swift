import SwiftData
import SwiftUI

struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }, sort: \Child.birthDate)
    private var children: [Child]

    @State private var family = FamilyService.shared
    @State private var role: GroupRole = .parent
    @State private var email = ""
    @State private var code: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                if let code {
                    generatedSection(code: code)
                } else {
                    optionsSection
                }
            }
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var optionsSection: some View {
        Group {
            Section {
                Picker("They will be", selection: $role) {
                    ForEach(GroupRole.allCases.filter { $0 != .owner }, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Access")
            } footer: {
                Text(role.blurb)
            }

            Section {
                TextField("Email (optional)", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
            } footer: {
                Text("Adding an email locks the code to that address. Leave it blank to read the code out loud instead, which is usually faster.")
            }

            Section {
                Button {
                    generate()
                } label: {
                    Text("Create invitation").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || (!email.isEmpty && !InviteLink.isValidEmail(email)))
            }
        }
    }

    private func generatedSection(code: String) -> some View {
        Group {
            Section {
                Text(code)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
            } footer: {
                Text("Works once, and expires in 48 hours.")
            }

            Section {
                ShareLink(
                    item: InviteMessage.text(
                        code: code,
                        role: role,
                        childName: children.first?.displayName
                    )
                ) {
                    Label("Send the invitation", systemImage: "square.and.arrow.up")
                }

                if !email.isEmpty,
                   let url = InviteMessage.emailURL(
                    address: email,
                    code: code,
                    role: role,
                    childName: children.first?.displayName
                   ) {
                    Link(destination: url) {
                        Label("Email it to \(email)", systemImage: "envelope")
                    }
                }
            } footer: {
                Text("The message carries a web link, not just the app link, so it opens on a laptop or on a phone that does not have Baby Docs yet.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func generate() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                code = try await family.generateInviteCode(
                    role: role,
                    email: email.isEmpty ? nil : email
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
