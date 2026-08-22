import StoreKit
import SwiftUI

/// The upgrade.
///
/// Weekly leads, which is unusual and deliberate. Almost every subscription app
/// leads with an annual plan because almost every subscription app is used for
/// years; this one is used for six to thirteen weeks and is then genuinely
/// finished. A weekly price is the honest one for a need that ends.
///
/// Lifetime sits underneath because the document vault is the part that does
/// not end, and a tier that keeps those photographs for good is a different
/// product from a tier that gets you through the deadlines.
///
/// Nothing on this page is sold that the app does not already do, and no
/// deadline, official link or document list is behind it.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreService.shared
    @State private var selection: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.looseSpacing) {
                    header
                    // Put the decision in the first viewport. The fixed purchase
                    // bar repeats the selected plan's terms, but it must never
                    // be the thing covering the trial line a buyer is comparing.
                    plans
                    benefits
                    subscriptionTerms
                    footerLinks
                }
                .padding(.horizontal, AppTheme.margin)
                .padding(.bottom, AppTheme.looseSpacing)
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
                    selection = store.plans.first { $0.id == ProProduct.weekly }?.id
                        ?? store.plans.first?.id
                }
            }
            .alert("Purchases", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: AppTheme.spacing) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("For the weeks it is actually happening")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Every deadline, document list and official link stays free. Plus is the work around them: keeping copies, chasing what has not come back, and the pages you hand to somebody else.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppTheme.spacing)
    }

    /// Every line here is a thing this build does today.
    ///
    /// Live sync between two phones is deliberately absent, because there is no
    /// server and there is not going to be one. Sending the plan to the other
    /// parent works, and it is free, so it is not sold here either.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            benefit("lock.doc", "The document vault",
                    "Photographs of the birth certificate, the card and the insurance details, on your phone at the counter. Never backed up, never uploaded.")
            benefit("clock.badge.exclamationmark", "Chase what has not arrived",
                    "Record what you sent and what you were told to expect. The plan speaks up when that date passes, because nothing else will.")
            benefit("briefcase", "The employer packet",
                    "The qualifying-life-event page HR asks for, with the event, the date and the enclosures already filled in.")
            benefit("figure.and.child.holdinghands", "Every child",
                    "A second baby inherits your household answers instead of asking again.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var plans: some View {
        VStack(spacing: AppTheme.spacing) {
            if store.plans.isEmpty {
                if let error = store.loadError {
                    // An empty list under a spinner reads as "nothing for sale".
                    // A customer who cannot see a price cannot buy, and cannot
                    // tell whether that is the app or their connection.
                    VStack(spacing: AppTheme.tightSpacing) {
                        Text("The App Store did not send the prices back.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            Task { await store.refresh() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, AppTheme.spacing)
                } else {
                    ProgressView().padding(.vertical, AppTheme.looseSpacing)
                }
            }
            ForEach(store.plans) { plan in
                Button {
                    // Selection, not completion. A success buzz for choosing a
                    // price tells the hand something was finished when nothing
                    // has been bought yet.
                    if selection != plan.id { Haptics.selected() }
                    selection = plan.id
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                            Text(plan.title).font(.body.weight(.medium))
                            Text(ProProduct.rationale(for: plan.id))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let intro = plan.introOffer {
                                Text(intro)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Spacer(minLength: AppTheme.spacing)
                        VStack(alignment: .trailing, spacing: AppTheme.hairSpacing) {
                            // Tabular figures because these three prices sit in
                            // a column being compared: proportional digits give
                            // "$4.99" and "$29.99" different decimal positions,
                            // and a price column that does not line up is read
                            // as carelessness on the one screen that cannot
                            // afford to be read that way.
                            Text(plan.price)
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                            if !plan.period.isEmpty {
                                Text(plan.period)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(AppTheme.spacing)
                    .background(
                        AppTheme.cardShape
                            .stroke(
                                selection == plan.id ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: selection == plan.id ? 2 : 1
                            )
                    )
                }
                .pressableCard()
                .accessibilityLabel(
                    "\(plan.title), \(plan.price) \(plan.period). \(plan.introOffer ?? "")"
                )
                .accessibilityValue(selection == plan.id ? "Selected" : "Not selected")
            }
        }
    }

    /// The disclosure App Review 3.1.2 requires, in the place the decision is
    /// actually made rather than in a terms page nobody opens.
    ///
    /// Built from the selected product rather than typed in, because a hardcoded
    /// sentence goes stale the first time a price or a trial length moves, and
    /// the failure mode is a paywall stating a price the store is not charging.
    /// Kept to one quiet paragraph: this has to be unmissable and true, not
    /// loud.
    private var subscriptionTerms: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            if let plan = store.plans.first(where: { $0.id == selection }) {
                Text(StoreService.disclosure(for: plan))
            }
            Text("Payment is charged to your Apple Account at confirmation. A subscription renews within 24 hours of the end of the current period unless cancelled first, and is managed in Settings, Apple Account, Subscriptions. Buying the one-time purchase forfeits any unused part of a free trial.")
            Text("What you add to the vault stays readable even if a subscription lapses. Lapsing stops you adding new documents; it never takes back the ones you have.")
        }
        // `caption2` for terms someone is agreeing to is a decision about
        // whether they read them. This is a purchase disclosure, not a footnote.
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The bar carries the selected plan's own price sentence, not just a verb.
    ///
    /// A sticky bar that says "Start my free trial" and nothing else puts the
    /// one sentence that says what is actually charged, and when, somewhere off
    /// screen: it sat in the terms block below the fold, in caption2, and on
    /// first presentation the bar was drawn across the selected card's trial
    /// line as well. Whatever is scrolled, the price, the period and the renewal
    /// are now in the same glance as the button that agrees to them.
    private var buyBar: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            if let plan = store.plans.first(where: { $0.id == selection }) {
                Text(StoreService.disclosure(for: plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            Button {
                purchase()
            } label: {
                Text(buyTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || store.isPro || selection == nil)

            Button("Restore purchases") { restore() }
                .font(.footnote)
        }
        .padding(.horizontal, AppTheme.margin)
        .padding(.vertical, AppTheme.spacing)
        .background(Color(uiColor: .systemBackground))
    }

    /// "Continue" tells a buyer nothing about what is about to happen. When the
    /// selected plan carries a trial, the button says so, because the difference
    /// between "charged now" and "charged in three days" is the whole reason
    /// somebody hesitates over this button.
    private var buyTitle: String {
        if store.isPro { return "You already have Plus" }
        guard let plan = store.plans.first(where: { $0.id == selection }) else { return "Continue" }
        if let intro = plan.introOffer, intro.hasSuffix("free") {
            return "Start my free trial"
        }
        return plan.isLifetime ? "Buy it once" : "Continue"
    }

    /// Both terms, not one.
    ///
    /// The App Store listing names Apple's Standard EULA and the app has terms
    /// of its own, and a buyer who taps "Terms" on the paywall should reach the
    /// same pair either way. Naming only one of them is the kind of mismatch
    /// between metadata and binary that a subscription review is looking for.
    private var footerLinks: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            HStack(spacing: AppTheme.looseSpacing) {
                Link("Terms of Use", destination: URL(string: "https://jackwallner.com/ios/babydocs/terms.html")!)
                Link("Privacy Policy", destination: URL(string: "https://jackwallner.com/ios/babydocs/privacy-policy.html")!)
            }
            Link("Apple Standard EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
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
                if store.isPro {
                    Haptics.purchased()
                    dismiss()
                }
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
                switch try await store.restore() {
                case .restored:
                    Haptics.purchased()
                    dismiss()
                case .nothingToRestore:
                    // Said plainly, because the alternative is a customer who
                    // already paid buying the same thing twice.
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
