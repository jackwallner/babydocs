import CoreLocation
import Foundation
import OSLog

/// One-shot "where am I" for the household questions, and nothing else.
///
/// Deliberately not a long-lived manager. It is created when a parent taps a
/// button, asks for a single fix, reverse-geocodes it into a state and county,
/// and is thrown away. Nothing here starts on launch, nothing runs in the
/// background, no coordinate is written to disk, and the only thing that
/// survives the call is two strings the parent can see and correct.
///
/// The result is a *suggestion* on the birth-state question and a *prefill* on
/// the residence one. That asymmetry is the whole reason this type exists rather
/// than a one-line CoreLocation call: where you are standing today is good
/// evidence about where you live and poor evidence about where you gave birth,
/// and a plan built on a silently wrong birth state sends a parent to the wrong
/// vital records office.
@MainActor
@Observable
final class LocationLookup: NSObject, CLLocationManagerDelegate {
    struct Place: Equatable, Sendable {
        var stateCode: String
        var county: String
    }

    enum Status: Equatable {
        case idle
        case asking
        case working
        case done(Place)
        case failed(String)
    }

    private(set) var status: Status = .idle

    private let manager = CLLocationManager()
    private let log = Logger(subsystem: "com.jackwallner.babydocs", category: "location")
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // Kilometre accuracy is plenty to name a county and asks the phone for
        // the cheapest, fastest fix available. Best accuracy here would cost
        // battery and seconds to locate a parent inside a building whose county
        // was never in doubt.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isBusy: Bool {
        switch status {
        case .asking, .working: return true
        default: return false
        }
    }

    /// True once the user has said no at the system level. The button then stops
    /// pretending it can help and points at Settings instead, because a second
    /// tap would do nothing at all and read as a broken control.
    var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    func find() async {
        guard !isBusy else { return }

        if manager.authorizationStatus == .notDetermined {
            status = .asking
            manager.requestWhenInUseAuthorization()
            // The delegate callback resolves this. Nothing is requested before
            // the answer arrives: asking for a location while the prompt is on
            // screen returns nothing and burns the one chance at the dialog.
            let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                authorizationContinuation = c
            }
            guard granted else {
                status = .failed("Location is off for Baby Docs. You can pick your state below.")
                return
            }
        }

        guard !isDenied else {
            status = .failed("Location is off for Baby Docs. You can pick your state below, or turn it on in Settings.")
            return
        }

        status = .working
        guard let location = await requestFix() else {
            status = .failed("Could not get a location just now. Pick your state below.")
            return
        }

        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let mark = marks.first,
                  mark.isoCountryCode == "US",
                  let code = mark.administrativeArea,
                  USState.named(code) != nil else {
                status = .failed("That does not look like a US address. Pick your state below.")
                return
            }
            let raw = mark.subAdministrativeArea ?? ""
            let county = USCounties.canonicalName(matching: raw, inStateCode: code) ?? raw
            status = .done(Place(stateCode: code.uppercased(), county: county))
        } catch {
            log.info("reverse geocode failed")
            status = .failed("Could not work out the county. Pick your state below.")
        }
    }

    func reset() {
        status = .idle
    }

    // MARK: - CoreLocation plumbing

    private var authorizationContinuation: CheckedContinuation<Bool, Never>?

    private func requestFix() async -> CLLocation? {
        await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            continuation = c
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined, let c = authorizationContinuation else { return }
            authorizationContinuation = nil
            c.resume(returning: status == .authorizedWhenInUse || status == .authorizedAlways)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let first = locations.first
        Task { @MainActor in
            continuation?.resume(returning: first)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}
