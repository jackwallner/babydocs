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

    var isLifetime: Bool { id == ProProduct.lifetime }
}

enum ProProduct {
    static let monthly = "com.jackwallner.babydocs.pro.monthly"
    static let yearly = "com.jackwallner.babydocs.pro.yearly"
    static let lifetime = "com.jackwallner.babydocs.pro.lifetime"

    /// Lifetime first, deliberately. The need this app serves is intense for
    /// about ninety days and then over, so a subscription is the wrong default
    /// to put in front of someone: they would cancel it, and a cancellation is a
    /// worse outcome for both sides than a one-time purchase.
    static let all: [String] = [lifetime, yearly, monthly]

    static func title(for productID: String) -> String {
        switch productID {
        case monthly: return "Monthly"
        case yearly: return "Yearly"
        case lifetime: return "One-time"
        default: return "Baby Docs Plus"
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
/// Everything that makes the plan worth having is free for one baby on one
/// phone: every task, every deadline, every document list, every official link.
/// Plus is the second parent and any further children. That split is the honest
/// one, because a deadline hidden behind a paywall is a deadline the app caused
/// someone to miss.
@MainActor
@Observable
final class StoreService: NSObject {
    static let shared = StoreService()

    private(set) var isPro: Bool = false
    private(set) var offerings: Offerings?
    private(set) var plans: [PlanOption] = []
    private(set) var isLoading: Bool = false

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
        Task {
            await identify()
            await refresh()
        }
    }

    /// Ties the RevenueCat customer to the Supabase user id, which is what makes
    /// the webhook able to find the payer's family. Without this the webhook
    /// sees an anonymous RevenueCat id, has nobody to credit, and the other
    /// parent silently never gets Plus.
    func identify() async {
        guard isConfigured, let userID = AuthService.shared.userID else { return }
        do {
            let (info, _) = try await Purchases.shared.logIn(userID.uuidString)
            apply(info)
        } catch {
            log.error("logIn failed: \(error.localizedDescription, privacy: .public)")
        }
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
            plans = (offerings.current?.availablePackages ?? []).map {
                PlanOption(
                    id: $0.storeProduct.productIdentifier,
                    title: ProProduct.title(for: $0.storeProduct.productIdentifier),
                    price: $0.storeProduct.localizedPriceString,
                    package: $0
                )
            }
        } catch {
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Populates `plans` from the local `.storekit` catalog. Only ever runs when
    /// RevenueCat is not configured, i.e. on the simulator.
    private func loadStoreKitTestingPlans() async {
        do {
            let products = try await Product.products(for: ProProduct.all)
            let order = ProProduct.all
            plans = products
                .sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
                .map {
                    PlanOption(
                        id: $0.id,
                        title: ProProduct.title(for: $0.id),
                        price: $0.displayPrice,
                        package: nil
                    )
                }
        } catch {
            log.error("StoreKit Testing load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase(_ plan: PlanOption) async throws {
        guard let package = plan.package else {
            // StoreKit Testing render only; there is nothing to charge against.
            return
        }
        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled else { return }
        apply(result.customerInfo)
        await propagateToFamily()
    }

    func restore() async throws {
        guard isConfigured else { return }
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
        await propagateToFamily()
    }

    /// The webhook is what actually writes `family_billing`, and it arrives
    /// server-to-server a moment later. This pulls the row so the other parent's
    /// entitlement is current on the payer's own device too.
    private func propagateToFamily() async {
        // Give the webhook a beat to land. Not load-bearing: the payer is
        // already unlocked locally either way, and the next foreground refresh
        // picks it up regardless.
        try? await Task.sleep(for: .seconds(2))
        await FamilyService.shared.refreshBilling()
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
