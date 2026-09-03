import StoreKit
import SwiftUI

/// The pitch and the purchase, in one place, wherever they are shown.
///
/// This used to live inside `PaywallView`, which was a sheet, which meant the
/// only way to reach the offer was to walk into a locked door. A pitch that is
/// only ever seen as a refusal is a pitch nobody chooses to read, so the same
/// view is now also a tab and the last page of the intake. One copy of the
/// benefit list, one copy of the 3.1.2 disclosure, one copy of the terms links:
/// three of those drifting apart is exactly how a paywall ends up promising
/// something the build does not do.
struct PlusPurchaseView: View {
    /// Where this is being shown. It changes the headline and nothing about
    /// what is sold.
    enum Placement {
        case sheet
        case tab
        case onboarding
    }

    var placement: Placement = .sheet
    /// Called after a purchase actually completes. The sheet dismisses; the
    /// intake moves on; the tab redraws itself as the tools.
    var onPurchased: (() -> Void)?
    /// The way past, where there has to be one. Present only in the intake,
    /// where this screen sits between a parent and the plan they just built.
    var onSkip: (() -> Void)?

    @State private var store = StoreService.shared
    @State private var selection: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.looseSpacing) {
                    header
                    // Put the decision in the first viewport. The purchase
                    // bar repeats the selected plan's terms, but it must
                    // never cover the benefit list while it is being read.
                    plans
                    benefits
                    freeLine
                    subscriptionTerms
                    footerLinks
                }
                .padding(.horizontal, AppTheme.margin)
                .padding(.bottom, AppTheme.looseSpacing)
            }
            buyBar
                .safeAreaPadding(.bottom)
        }
        .task { await refreshStore() }
        .alert("Purchases", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Pitch

    private var header: some View {
        VStack(spacing: AppTheme.spacing) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text(headline)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("The list of what applies to you is free, and so are both dates that legally close. Plus is the part that tells you when to do the rest, in what order, and says something before each one arrives.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, AppTheme.spacing)
    }

    private var headline: String {
        switch placement {
        case .onboarding: return "Your plan knows the dates. Plus tells you when."
        case .tab, .sheet: return "For the weeks it is actually happening"
        }
    }

    /// Every line here is a thing this build does today.
    ///
    /// Live sync between two phones is deliberately absent, because there is no
    /// server and there is not going to be one. Sending the plan to the other
    /// parent works, every child is free, so neither is sold here.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            benefit("bell.badge", "A reminder for every date, not just the two that close",
                    "Most of your plan is dates Baby Docs suggests rather than dates the law sets. Free warns you about the two legal windows. Plus warns you about the rest, three days out, and lets you set your own on any task.")
            benefit("list.number", "The order to do it in",
                    "The passport is really the birth certificate wearing a hat, and the $1,000 election is the Social Security card wearing one. Plus shows the plan as a sequence: what to start this week, what is next, and what is simply waiting on something else to arrive.")
            benefit("calendar", "This week's paperwork, every Sunday",
                    "One message on a Sunday morning naming what reaches its date that week, and nothing at all on a week that holds nothing.")
            benefit("calendar.badge.plus", "The dates in your own calendar",
                    "Export the plan as a calendar file, so the deadlines sit beside the pediatrician appointment they are competing with, where the other parent can see them too.")
            benefit("clock.badge.exclamationmark", "Chase what has not arrived",
                    "Record what you sent and what you were told to expect. The plan speaks up when that date passes, because nothing else will.")
            benefit("lock.doc", "The document vault after twelve weeks",
                    "Photographs of the birth certificate, the card and the insurance details, on your phone at the counter. Adding stays free during the first twelve weeks. Never backed up, never uploaded.")
            benefit("doc.text", "The printable summary and the employer packet",
                    "A plain-text plan for the folder or the other parent, and the qualifying-life-event page HR asks for with the event, the date and the enclosures already filled in.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Said out loud on the paywall, because a customer who cannot tell what
    /// they already have cannot tell what they are buying.
    private var freeLine: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Text("Free, and staying free")
                .font(.subheadline.weight(.semibold))
            Text("Every task that applies to your household, every official link, every document list, reminders for both deadlines that legally close, every child you add, and sending the whole plan to the other parent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .planCard()
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Plans

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
                            Task { await refreshStore() }
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
                    planRow(plan)
                }
                .pressableCard()
                .accessibilityLabel(
                    "\(plan.title), \(plan.price) \(plan.period). \(plan.introOffer ?? "")"
                )
                .accessibilityValue(selection == plan.id ? "Selected" : "Not selected")
            }
        }
    }

    private func planRow(_ plan: PlanOption) -> some View {
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
                // Tabular figures because these three prices sit in a column
                // being compared: proportional digits give "$4.99" and "$29.99"
                // different decimal positions, and a price column that does not
                // line up is read as carelessness on the one screen that cannot
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

    private func refreshStore() async {
        // This app reported no paywall impressions at all until now, so
        // everything between "installed" and "subscribed" was invisible for it
        // in RevenueCat.
        store.trackPaywallImpression(id: "babydocs_\(placement)", oncePerSession: true)
        await store.refresh()
        let available = Set(store.plans.map(\.id))
        if let selection, available.contains(selection) { return }
        selection = store.plans.first { $0.id == ProProduct.weekly }?.id
            ?? store.plans.first?.id
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
            Text("Payment is charged to your Apple Account at confirmation. A subscription renews automatically within 24 hours of the end of the current period unless cancelled first, and is managed in Settings, Apple Account, Subscriptions. Buying the one-time purchase forfeits any unused part of a free trial.")
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

            if let onSkip {
                Button("Continue with the free plan", action: onSkip)
                    .font(.footnote)
            } else {
                Button("Restore purchases") { restore() }
                    .font(.footnote)
            }
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
            // In the intake the trial *is* the way forward, so the button says
            // what it is doing in the intake's own words. The price, the period
            // and the renewal are printed directly above it either way, and
            // Apple's own sheet still has to be confirmed after it, so nothing
            // here is hidden by the shorter verb.
            return placement == .onboarding ? "Get started" : "Start my free trial"
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.looseSpacing) {
                    Link("Terms of Use", destination: URL(string: "https://jackwallner.com/ios/babydocs/terms.html")!)
                    Link("Privacy Policy", destination: URL(string: "https://jackwallner.com/ios/babydocs/privacy-policy.html")!)
                }
                VStack(spacing: AppTheme.hairSpacing) {
                    Link("Terms of Use", destination: URL(string: "https://jackwallner.com/ios/babydocs/terms.html")!)
                    Link("Privacy Policy", destination: URL(string: "https://jackwallner.com/ios/babydocs/privacy-policy.html")!)
                }
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
                    onPurchased?()
                }
            } catch {
                errorMessage = "The purchase could not be completed. Check your Apple Account and try again."
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
                    onPurchased?()
                case .nothingToRestore:
                    // Said plainly, because the alternative is a customer who
                    // already paid buying the same thing twice.
                    errorMessage = "No previous purchase was found for this Apple Account. If you bought Plus with a different account, sign in with that one and try again."
                case .unavailable:
                    errorMessage = "Purchases cannot be restored in this build."
                }
            } catch {
                errorMessage = "Purchases could not be restored right now. Check your Apple Account and try again."
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlusPurchaseView(placement: .tab)
            .navigationTitle("Baby Docs Plus")
            .navigationBarTitleDisplayMode(.inline)
    }
}
