package com.jackwallner.babydocs.data

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.babydocs.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import kotlin.coroutines.cancellation.CancellationException

enum class PurchaseOutcome { PURCHASED, PENDING, CANCELLED }

internal fun purchaseOutcome(code: PurchasesErrorCode, userCancelled: Boolean): PurchaseOutcome? = when {
    userCancelled || code == PurchasesErrorCode.PurchaseCancelledError -> PurchaseOutcome.CANCELLED
    code == PurchasesErrorCode.PaymentPendingError -> PurchaseOutcome.PENDING
    else -> null
}

class PurchaseException(message: String) : Exception(message)

private fun Period.toPlanPeriod(): PlanPeriod? {
    val unit = when (unit) {
        Period.Unit.DAY -> PeriodUnit.DAY
        Period.Unit.WEEK -> PeriodUnit.WEEK
        Period.Unit.MONTH -> PeriodUnit.MONTH
        Period.Unit.YEAR -> PeriodUnit.YEAR
        else -> return null
    }
    return PlanPeriod(value, unit)
}

/**
 * RevenueCat behind Baby Docs Plus (`StoreService.swift`). Debug builds use the
 * project's Test Store key and release builds the Play key; neither ever runs
 * on the other. Plus is the `BabyDocs+` entitlement, or one of the legacy
 * lookup keys iOS still honours, so a payer is never locked out by a rename.
 */
class SubscriptionService(
    private val context: Context,
    private val defaults: KeyValueStore,
    private val diagnostics: ConversionDiagnostics,
) {
    private val reviewAccess = ReviewAccess(defaults, BuildConfig.PLAY_REVIEW_CODE_SHA256)
    private var entitlementActive by mutableStateOf(defaults.getBoolean(CACHED_PRO))
    private var overrideActive by mutableStateOf(BuildConfig.DEBUG && defaults.getBoolean(LOCAL_OVERRIDE))
    private var reviewGranted by mutableStateOf(reviewAccess.isGranted)

    /** The single gate the whole app reads. */
    val isPro: Boolean get() = entitlementActive || overrideActive || reviewGranted

    val hasReviewAccess: Boolean get() = reviewGranted

    var isConfigured by mutableStateOf(false)
        private set
    var isLoadingProducts by mutableStateOf(false)
        private set
    var lastError by mutableStateOf<String?>(null)
        private set
    var plans by mutableStateOf<List<Plan>>(emptyList())
        private set
    /** Until customer info has answered, never promise a trial (it may already be used). */
    private var introEligibilityResolved by mutableStateOf(false)
    private var hasSubscriptionHistory by mutableStateOf(false)

    private var packages: List<Package> = emptyList()
    private var offering: Offering? = null
    private var customerInfoLoaded = false
    private var isPreview = false
    private val impressionsThisSession = mutableSetOf<String>()

    fun setLocalOverride(value: Boolean) {
        if (!BuildConfig.DEBUG) return
        defaults.putBoolean(LOCAL_OVERRIDE, value)
        overrideActive = value
    }

    /** Debug screenshots and UI tests: a local plan stack with no store behind it. */
    fun loadPreviewPlans(preview: List<Plan>, trialUsed: Boolean = false) {
        if (!BuildConfig.DEBUG) return
        plans = preview
        packages = emptyList()
        hasSubscriptionHistory = trialUsed
        introEligibilityResolved = true
        isConfigured = true
        isPreview = true
        lastError = null
    }

    fun activateReviewAccess(code: String): Boolean {
        if (!reviewAccess.activate(code)) return false
        reviewGranted = true
        return true
    }

    suspend fun start() {
        if (!configureIfNeeded()) return
        refreshCustomerInfo()
        fetchProducts()
    }

    suspend fun refreshCustomerInfo() {
        if (isPreview || !configureIfNeeded()) return
        runCatching { Purchases.sharedInstance.awaitCustomerInfo() }
            .onSuccess(::apply)
            .onFailure { if (it is CancellationException) throw it }
    }

    suspend fun fetchProducts() {
        if (isPreview || isLoadingProducts) return
        if (!configureIfNeeded()) {
            lastError = "Google Play did not send the prices back. Check your connection and try again."
            return
        }
        isLoadingProducts = true
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val offering = offerings.all[OFFERING_ID] ?: offerings.current
            val loaded = offering?.availablePackages.orEmpty().sortedWith(
                compareBy<Package> { kind(it).ordinal }.thenBy { it.product.id },
            )
            this.offering = offering
            packages = loaded
            plans = loaded.map(::plan)
            lastError = if (loaded.isEmpty()) "Google Play did not send the prices back. Check your connection and try again." else null
            if (!customerInfoLoaded) refreshCustomerInfo()
            introEligibilityResolved = customerInfoLoaded
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            lastError = "Google Play did not send the prices back. Check your connection and try again."
        } finally {
            isLoadingProducts = false
        }
    }

    /** Defaults to not eligible until RevenueCat answers, so nobody is promised a trial they already used. */
    fun isEligibleForIntroOffer(plan: Plan): Boolean =
        plan.trial != null && introEligibilityResolved && !hasSubscriptionHistory

    /** Feeds RevenueCat's paywall encounters; a custom paywall emits none of its own. */
    fun trackPaywallImpression(id: String, oncePerSession: Boolean = false) {
        if (oncePerSession && !impressionsThisSession.add(id)) return
        diagnostics.recordPitchView(id)
        if (!isConfigured || isPreview) return
        syncConversionAttributes()
        val params = offering?.let { CustomPaywallImpressionParams(id, it) } ?: CustomPaywallImpressionParams(id)
        runCatching { Purchases.sharedInstance.trackCustomPaywallImpression(params) }
    }

    fun syncConversionAttributes() {
        if (!isConfigured || isPreview) return
        val attributes = diagnostics.subscriberAttributes
        if (attributes.isEmpty()) return
        runCatching { Purchases.sharedInstance.setAttributes(attributes) }
    }

    /** A cancel is an outcome, not an error. Throws only with a user-facing message. */
    suspend fun purchase(activity: Activity, plan: Plan): PurchaseOutcome {
        if (isPreview) {
            setLocalOverride(true)
            return PurchaseOutcome.PURCHASED
        }
        val pkg = packages.firstOrNull { it.identifier == plan.packageId }
        if (!configureIfNeeded() || pkg == null) throw PurchaseException(UNAVAILABLE)
        val startedTrial = isEligibleForIntroOffer(plan)
        val option = if (startedTrial) pkg.product.defaultOption else pkg.product.subscriptionOptions?.basePlan
        val params = if (option != null) {
            PurchaseParams.Builder(activity, option).presentedOfferingContext(pkg.presentedOfferingContext).build()
        } else {
            PurchaseParams.Builder(activity, pkg).build()
        }
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(params)
            apply(result.customerInfo)
            if (!entitlementActive) refreshCustomerInfo()
            if (!entitlementActive) return PurchaseOutcome.PENDING
            diagnostics.recordConversion(pkg.product.id, startedTrial, pkg.presentedOfferingContext.offeringIdentifier)
            syncConversionAttributes()
            PurchaseOutcome.PURCHASED
        } catch (error: PurchasesTransactionException) {
            purchaseOutcome(error.code, error.userCancelled)
                ?: throw PurchaseException("The purchase could not be completed. Check your Google Play account and try again.")
        }
    }

    /** Leaves [lastError] set when nothing was restored, like iOS. */
    suspend fun restorePurchases() {
        lastError = null
        if (isPreview) return
        if (!configureIfNeeded()) {
            lastError = UNAVAILABLE
            return
        }
        try {
            apply(Purchases.sharedInstance.awaitRestore())
            if (!entitlementActive) lastError = "No previous purchase was found for this Google Play account. If you bought Plus with a different account, switch to that one in Google Play and try again."
        } catch (error: CancellationException) {
            throw error
        } catch (error: PurchasesException) {
            lastError = if (error.code == PurchasesErrorCode.PaymentPendingError) {
                "Google Play is still processing your payment. Plus unlocks as soon as it completes."
            } else {
                "Purchases could not be restored right now. Check your Google Play account and try again."
            }
        } catch (_: Throwable) {
            lastError = "Purchases could not be restored right now. Check your Google Play account and try again."
        }
    }

    private fun apply(info: CustomerInfo) {
        customerInfoLoaded = true
        hasSubscriptionHistory = info.allExpirationDatesByProduct.isNotEmpty()
        introEligibilityResolved = packages.isNotEmpty()
        entitlementActive = ENTITLEMENTS.any { info.entitlements[it]?.isActive == true }
        defaults.putBoolean(CACHED_PRO, entitlementActive)
    }

    private fun configureIfNeeded(): Boolean {
        if (isConfigured) return true
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        // Never the production Play key in a debug build, and never a test key in release.
        if (BuildConfig.DEBUG && key.startsWith("goog_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        Purchases.configure(PurchasesConfiguration.Builder(context, key).build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        isConfigured = true
        return true
    }

    private fun kind(pkg: Package): PackageKind = when (pkg.packageType) {
        PackageType.LIFETIME -> PackageKind.LIFETIME
        PackageType.ANNUAL -> PackageKind.YEARLY
        PackageType.MONTHLY -> PackageKind.MONTHLY
        PackageType.WEEKLY -> PackageKind.WEEKLY
        else -> PackageKind.fromIdentifiers(pkg.identifier, pkg.product.id)
    }

    private fun plan(pkg: Package): Plan {
        val price = pkg.product.price
        val free = pkg.product.subscriptionOptions?.firstOrNull { it.freePhase != null }?.freePhase
            ?: pkg.product.defaultOption?.freePhase
        return Plan(
            packageId = pkg.identifier,
            productId = pkg.product.id,
            kind = kind(pkg),
            priceMicros = price.amountMicros,
            priceFormatted = price.formatted,
            currencyCode = price.currencyCode,
            period = pkg.product.period?.toPlanPeriod(),
            trial = free?.billingPeriod?.toPlanPeriod(),
            title = pkg.product.title,
        )
    }

    companion object {
        private const val OFFERING_ID = "default"
        val ENTITLEMENTS = listOf("BabyDocs+", "pro", "BabyDocsPro")
        private const val LOCAL_OVERRIDE = "subscription.localProOverride"
        private const val CACHED_PRO = "babydocs.isPlus"
        private const val UNAVAILABLE = "Google Play is not reachable right now. Check your connection and try again."

        const val PENDING_MESSAGE = "The purchase is waiting for approval. Plus unlocks as soon as Google Play approves it."
        const val AUTO_RENEW_DISCLOSURE =
            "Auto-renews unless cancelled before the end of the current period. Manage or cancel in Google Play › Payments & subscriptions."
    }
}

internal fun String.capitalizeWords(): String =
    split(" ").joinToString(" ") { word -> word.split("-").joinToString("-") { it.replaceFirstChar(Char::uppercaseChar) } }
