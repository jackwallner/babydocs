import Foundation
import StoreKit
import os
@preconcurrency import RevenueCat

/// One purchasable plan, decoupled from where it came from.
///
/// On device the source is a RevenueCat `Package`. On the simulator RevenueCat
/// is never configured (see `configureIfNeeded`), so plans come straight from
/// StoreKit Testing instead. Without this the paywall can only ever render its
/// empty state on a sim, which makes the layout unverifiable.
struct PlanOption: Identifiable, Sendable {
    let id: String
    let title: String
    let price: String
    let package: Package?
    /// "per month", "per year", or "one-time payment". Rendered next to the
    /// price, because a price with no period beside it is the single most
    /// common way a subscription purchase surprises the person who made it.
    var period: String = ""
    /// "3 days free, then ..." when the product carries an introductory offer.
    /// Nil when it does not, or when eligibility could not be determined.
    var introOffer: String?

    var isLifetime: Bool { id == ProProduct.lifetime }
}

enum ProProduct {
    static let weekly = "com.jackwallner.babydocs.pro.weekly"
    static let yearly = "com.jackwallner.babydocs.pro.yearly"
    static let lifetime = "com.jackwallner.babydocs.pro.lifetime"

    /// Weekly first, and that is unusual on purpose.
    ///
    /// Almost every subscription app leads with an annual plan because almost
    /// every subscription app is used for years. This one is not: the paperwork
    /// is intense for six to thirteen weeks and then genuinely finished. A
    /// weekly price is the honest one for a need that ends, and someone who uses
    /// it for eight weeks pays for eight weeks.
    ///
    /// Lifetime sits underneath it because the vault is the part that does not
    /// end. Those photographs are still useful at kindergarten registration, so
    /// the tier that keeps them is sold as a thing you own. The yearly sits
    /// between the two and mostly exists to make the comparison legible.
    static let all: [String] = [weekly, yearly, lifetime]

    static func title(for productID: String) -> String {
        switch productID {
        case weekly: return "Weekly"
        case yearly: return "Yearly"
        case lifetime: return "Keep it forever"
        default: return "Baby Docs Plus"
        }
    }

    /// One line under each plan saying what it is *for*, which is the question a
    /// price does not answer. A parent choosing between $4.99 a week and $59.99
    /// once is really choosing between "until this is over" and "for good", and
    /// nothing on a price row says that.
    static func rationale(for productID: String) -> String {
        switch productID {
        case weekly: return "For the weeks the paperwork is actually happening."
        case yearly: return "If you would rather not think about it again this year."
        case lifetime: return "Keeps the document vault for good. No renewal."
        default: return ""
        }
    }
}

enum RevenueCatConfig {
    static let apiKey = "appl_LIrLhMIPlUeqSjOlWhYtkPSTvtP"
    /// Entitlement identifier as configured on the RevenueCat dashboard. Not
    /// the fleet-default "pro", so checking only "pro" would leave a paying
    /// customer locked out.
    static let proEntitlement = "BabyDocs+"
    /// Kept so a purchase made against an alternate identifier still unlocks.
    static let fallbackEntitlements = ["pro", "BabyDocsPro"]
}

/// Freemium gate.
///
/// Everything that makes the plan worth having is free for one baby: every task,
/// every deadline, every document list, every official link, every reminder, and
/// sending the plan to the other parent. A deadline hidden behind a paywall is a
/// deadline the app caused someone to miss, so no date in this app is ever
/// behind one.
///
/// Plus is the work *around* the deadlines: keeping copies of the documents,
/// chasing the things that were sent and have not come back, the printable plan
/// and the employer packet, and further children.
@MainActor
@Observable
final class StoreService: NSObject {
    static let shared = StoreService()

    private(set) var isPro: Bool = false
    private(set) var offerings: Offerings?
    private(set) var plans: [PlanOption] = []
    private(set) var isLoading: Bool = false
    /// Set when the products could not be loaded. Observable rather than only
    /// logged, because the paywall's silent failure mode is an empty list with a
    /// spinner over it, which reads as "nothing for sale" rather than "try
    /// again".
    private(set) var loadError: String?

    private var isConfigured = false
    private var localOverride: Bool?
    private let log = Logger(subsystem: "com.jackwallner.babydocs", category: "store")

    private override init() {
        super.init()
    }

    /// Dev/sim escape hatch so paywalled screens can be driven without a purchase.
    func setLocalOverride(isPro value: Bool?) {
        localOverride = value
        if let value {
            isPro = value
        }
    }

    func start() {
        configureIfNeeded()
        Task { await refresh() }
    }

    func refresh() async {
        if let localOverride {
            isPro = localOverride
        }

        isLoading = true
        defer { isLoading = false }

        guard isConfigured else {
            // Simulator: no RevenueCat, so fall back to StoreKit Testing products.
            await loadStoreKitTestingPlans()
            return
        }

        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
            let offerings = try await Purchases.shared.offerings()
            self.offerings = offerings
            // RevenueCat returns packages in the order they were created in the
            // dashboard, and there is no reorder endpoint in either the v2 or
            // the internal API. That put annual first and weekly last, which
            // inverts the whole pricing argument: weekly leads because the need
            // ends. `ProProduct.all` already declares the intended order, so
            // sort against it and let the dashboard hold whatever order it likes.
            let ordered = (offerings.current?.availablePackages ?? []).sorted {
                let left = ProProduct.all.firstIndex(of: $0.storeProduct.productIdentifier)
                    ?? ProProduct.all.count
                let right = ProProduct.all.firstIndex(of: $1.storeProduct.productIdentifier)
                    ?? ProProduct.all.count
                return left < right
            }
            plans = ordered.map { package in
                let product = package.storeProduct
                return PlanOption(
                    id: product.productIdentifier,
                    title: ProProduct.title(for: product.productIdentifier),
                    price: product.localizedPriceString,
                    package: package,
                    period: Self.periodLabel(
                        unit: product.subscriptionPeriod?.unit.calendarUnitLabel,
                        count: product.subscriptionPeriod?.value
                    ),
                    introOffer: product.introductoryDiscount.map {
                        Self.introLabel(
                            isFree: $0.paymentMode == .freeTrial,
                            price: $0.localizedPriceString,
                            unit: $0.subscriptionPeriod.unit.calendarUnitLabel,
                            count: $0.subscriptionPeriod.value
                        )
                    }
                )
            }
            loadError = plans.isEmpty ? "No plans came back from the store." : nil
        } catch {
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
        }
    }

    // MARK: - Disclosure copy

    /// "per month" / "per year" / "one-time payment". Apple requires the billing
    /// period beside the price for an auto-renewing product, and a buyer
    /// deserves it whether or not Apple asked.
    static func periodLabel(unit: String?, count: Int?) -> String {
        guard let unit, let count, count > 0 else { return "one-time payment" }
        return count == 1 ? "per \(unit)" : "every \(count) \(unit)s"
    }

    /// "3 days free" or "$0.99 for the first month".
    ///
    /// Deliberately no "then the price below": the price is six points to the
    /// right on the same row, so the phrase pointed at something already in
    /// view and read as filler. The full renewal sentence is `disclosure`, which
    /// sits under the buttons where App Review looks for it.
    static func introLabel(isFree: Bool, price: String, unit: String, count: Int) -> String {
        let span = count == 1 ? "1 \(unit)" : "\(count) \(unit)s"
        return isFree ? "\(span) free" : "\(price) for the first \(span)"
    }

    /// The disclosure App Review 3.1.2 requires, built from the product rather
    /// than typed into the view. A hardcoded sentence goes stale the first time
    /// a price or a trial length changes, and the failure mode is a paywall that
    /// states a price the store is not charging.
    static func disclosure(for plan: PlanOption) -> String {
        guard !plan.isLifetime, !plan.period.isEmpty else {
            return "One payment. No subscription, nothing to cancel."
        }
        let renewal = "Renews at \(plan.price) \(plan.period) until cancelled. Cancel any time in Settings."
        guard let intro = plan.introOffer, intro.hasSuffix("free") else { return renewal }
        return "\(intro), then \(plan.price) \(plan.period). \(renewal)"
    }

    /// Populates `plans` from the local `.storekit` catalog. Only ever runs when
    /// RevenueCat is not configured, i.e. on the simulator.
    private func loadStoreKitTestingPlans() async {
        do {
            let products = try await Product.products(for: ProProduct.all)
            let order = ProProduct.all
            plans = products
                .sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
                .map { product in
                    let subscription = product.subscription
                    return PlanOption(
                        id: product.id,
                        title: ProProduct.title(for: product.id),
                        price: product.displayPrice,
                        package: nil,
                        period: Self.periodLabel(
                            unit: subscription?.subscriptionPeriod.unit.calendarUnitLabel,
                            count: subscription?.subscriptionPeriod.value
                        ),
                        introOffer: subscription?.introductoryOffer.map {
                            Self.introLabel(
                                isFree: $0.paymentMode == .freeTrial,
                                price: $0.displayPrice,
                                unit: $0.period.unit.calendarUnitLabel,
                                count: $0.period.value
                            )
                        }
                    )
                }
            loadError = plans.isEmpty ? "No plans came back from the store." : nil
        } catch {
            log.error("StoreKit Testing load failed: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
        }

        #if DEBUG
        // A UI test host gets no StoreKit configuration: Xcode attaches the
        // `.storekit` file to the *launch* action only, so `Product.products`
        // comes back empty and the paywall renders its "no prices" state. That
        // makes the one screen where price, billing period and renewal
        // disclosure have to appear together the one screen a screenshot can
        // never check, which is exactly backwards.
        //
        // So on a simulator with nothing loaded, fall back to display-only
        // plans. They carry no `Package`, so `purchase(_:)` already returns
        // without charging anything, and this whole block is compiled out of
        // release.
        if plans.isEmpty {
            plans = Self.placeholderPlans
            loadError = nil
        }
        #endif
    }

    #if DEBUG
    /// Layout stand-ins, so a screenshot of the paywall is a screenshot of the
    /// paywall. The numbers mirror `Products.storekit`; if they drift, the
    /// picture is wrong rather than the app.
    private static let placeholderPlans: [PlanOption] = [
        PlanOption(
            id: ProProduct.weekly,
            title: ProProduct.title(for: ProProduct.weekly),
            price: "$4.99",
            package: nil,
            period: "per week",
            introOffer: "3 days free"
        ),
        PlanOption(
            id: ProProduct.yearly,
            title: ProProduct.title(for: ProProduct.yearly),
            price: "$29.99",
            package: nil,
            period: "per year"
        ),
        PlanOption(
            id: ProProduct.lifetime,
            title: ProProduct.title(for: ProProduct.lifetime),
            price: "$59.99",
            package: nil,
            period: ""
        )
    ]
    #endif

    func purchase(_ plan: PlanOption) async throws {
        guard let package = plan.package else {
            // StoreKit Testing render only; there is nothing to charge against.
            return
        }
        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled else { return }
        apply(result.customerInfo)
    }

    /// What a restore actually did. "Nothing happened" and "nothing was there to
    /// restore" look identical from a button that only throws, and the second is
    /// the case a customer needs told plainly before they buy twice.
    enum RestoreOutcome: Sendable {
        case restored
        case nothingToRestore
        case unavailable
    }

    @discardableResult
    func restore() async throws -> RestoreOutcome {
        guard isConfigured else { return .unavailable }
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
        return isPro ? .restored : .nothingToRestore
    }

    private func apply(_ info: CustomerInfo) {
        guard localOverride == nil else { return }
        let identifiers = [RevenueCatConfig.proEntitlement] + RevenueCatConfig.fallbackEntitlements
        isPro = identifiers.contains { info.entitlements[$0]?.isActive == true }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        // Agent/simulator runs must never create customers in the production
        // RevenueCat project. Use local UI state and StoreKit Testing instead.
        //
        // `#else` rather than an early `return`, which would make every line
        // after it unreachable on a simulator build and so warn on every such
        // build, burying anything else the compiler had to say.
        #if !targetEnvironment(simulator)
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        isConfigured = true
        #endif
    }
}

// MARK: - Period units

/// The two SDKs describe a billing period with two different enums, and the
/// paywall needs one word out of either.
extension RevenueCat.SubscriptionPeriod.Unit {
    var calendarUnitLabel: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}

extension Product.SubscriptionPeriod.Unit {
    var calendarUnitLabel: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}
