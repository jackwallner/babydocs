import Foundation
import RevenueCat
import Testing

@testable import BabyDocs

/// Ask to Buy reads as waiting, a lost connection reads as the store line, and
/// everything else keeps the message the paywall always showed.
struct PurchaseFailureTests {
    @Test("A pending Ask to Buy is waiting for approval, not a failure")
    func pendingIsWaiting() {
        let failure = PurchaseFailure(ErrorCode.paymentPendingError)
        #expect(failure == .waitingForApproval)
        #expect(failure.message == "Waiting for approval. Your purchase unlocks once it is approved.")
        #expect(!failure.message.localizedCaseInsensitiveContains("could not"))
    }

    @Test("RevenueCat's error bridged to NSError maps the same way")
    func bridgedErrorMaps() {
        let bridged = ErrorCode.paymentPendingError as NSError
        #expect(PurchaseFailure(bridged) == .waitingForApproval)
        #expect(PurchaseFailure(ErrorCode.offlineConnectionError as NSError) == .storeUnreachable)
    }

    @Test("Network and offline errors read as the store line")
    func networkIsUnreachable() {
        #expect(PurchaseFailure(ErrorCode.networkError) == .storeUnreachable)
        #expect(PurchaseFailure(ErrorCode.offlineConnectionError) == .storeUnreachable)
        #expect(PurchaseFailure.storeUnreachable.message
            == "The store could not be reached. Check your connection and try again.")
    }

    @Test("Other errors keep the message the paywall always showed")
    func otherErrorsUnchanged() {
        #expect(PurchaseFailure(ErrorCode.purchaseNotAllowedError) == .failed)
        #expect(PurchaseFailure(ErrorCode.storeProblemError) == .failed)
        #expect(PurchaseFailure(NSError(domain: "elsewhere", code: 7)) == .failed)
        #expect(PurchaseFailure.failed.message
            == "The purchase could not be completed. Check your Apple Account and try again.")
    }

    @Test("A failure already mapped passes through")
    func mappedPassesThrough() {
        #expect(PurchaseFailure(PurchaseFailure.waitingForApproval) == .waitingForApproval)
    }
}
