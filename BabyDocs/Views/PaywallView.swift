import StoreKit
import SwiftUI

/// The upgrade.
///
/// One-time purchase first, and that is a product decision rather than a layout
/// one. The need this app serves is intense for about ninety days and then
/// genuinely over. Leading with a subscription would sell something the customer
/// will cancel, and a cancellation is worse for both sides than a purchase that
/// simply stays bought.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreService.shared
    @State private var selection: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    benefits
                    plans
                    footerLinks
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) { buyBar }
            .navigationTitle("Baby Docs Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await store.refresh()
                if selection == nil {
                    selection = store.plans.first(where: \.isLifetime)?.id ?? store.plans.first?.id
                }
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("The whole plan, on one page")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Every deadline, every document list and every official link is free for one baby. Plus is the summary you can hand to someone else, and room for the next one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    /// Sharing is deliberately absent here. `SupabaseConfig.isConfigured` is
    /// false in shipping builds, so a bullet promising the other parent would be
    /// selling a feature this binary cannot deliver. It goes back when sharing
    /// is switched on, and not a build before.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefit("figure.and.child.holdinghands", "Every child",
                    "A second baby inherits your household answers instead of asking again.")
            benefit("square.and.arrow.up", "The printable one-pager",
                    "What is left, what to bring, and every confirmation number, on one page.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var plans: some View {
        VStack(spacing: 10) {
            if store.plans.isEmpty {
                ProgressView().padding(.vertical, 20)
            }
            ForEach(store.plans) { plan in
                Button {
                    selection = plan.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.title).font(.body.weight(.medium))
                            if plan.isLifetime {
                                Text("Pay once. No renewal.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(plan.price).font(.body.weight(.semibold))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                            .stroke(
                                selection == plan.id ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: selection == plan.id ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var buyBar: some View {
        VStack(spacing: 8) {
            Button {
                purchase()
            } label: {
                Text(store.isPro ? "You already have Plus" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || store.isPro || selection == nil)

            Button("Restore purchases") { restore() }
                .font(.footnote)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var footerLinks: some View {
        HStack(spacing: 14) {
            Link("Terms", destination: URL(string: "https://jackwallner.com/ios/babydocs/terms.html")!)
            Link("Privacy", destination: URL(string: "https://jackwallner.com/ios/babydocs/privacy-policy.html")!)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func purchase() {
        guard let plan = store.plans.first(where: { $0.id == selection }) else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await store.purchase(plan)
                if store.isPro { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await store.restore()
                if store.isPro { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
