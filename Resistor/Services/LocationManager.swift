import Foundation
import CoreLocation
import Observation
import SwiftData

protocol LocationProviding {
    var isAuthorized: Bool { get }
    @MainActor func requestCurrentLocation() async -> CLLocation?
    func reverseGeocode(latitude: Double, longitude: Double) async -> String?
}

extension LocationProviding {
    /// Stamps a saved event with where it happened, then saves again. Shared by
    /// the phone's `LogViewModel` and the watch's `WatchLogStore` so a wrist log
    /// carries the same location data as a phone log.
    ///
    /// Deliberately best-effort and fire-and-forget: the event is already
    /// persisted before this runs, so an unauthorized, denied, or timed-out fix
    /// just leaves it without a location rather than failing the log. On the
    /// watch that includes the app being suspended (wrist down) before the fix
    /// arrives.
    @MainActor
    func attachLocation(to event: TemptationEvent, in context: ModelContext) async {
        guard isAuthorized, let location = await requestCurrentLocation() else { return }

        let placeName = await reverseGeocode(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        // Undo can delete the event while the fix is still in flight — the
        // phone's 5s banner window, a wrist shake on the watch. Both awaits are
        // above this line, so one check covers them: writing to a deleted model
        // object would resurrect an event the user just took back.
        guard !event.isDeleted else { return }

        event.latitude = location.coordinate.latitude
        event.longitude = location.coordinate.longitude
        if let placeName {
            event.locationName = placeName
        }

        do {
            try context.save()
        } catch {
            print("Failed to save location for event: \(error)")
        }
    }
}

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate, LocationProviding {
    private let clManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = clManager.authorizationStatus
    }

    func requestPermission() {
        clManager.requestWhenInUseAuthorization()
    }

    @MainActor
    func requestCurrentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }

        // Prevent overlapping requests — if one is already in flight, bail out
        guard locationContinuation == nil else { return nil }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            clManager.requestLocation()
        }
    }

    func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            // Build a concise place name: "Neighborhood, City" or "City, State"
            let components = [placemark.subLocality, placemark.locality, placemark.administrativeArea]
            let filtered = components.compactMap { $0 }
            guard !filtered.isEmpty else { return nil }
            return filtered.prefix(2).joined(separator: ", ")
        } catch {
            print("Reverse geocoding failed: \(error)")
            return nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationContinuation?.resume(returning: locations.last)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location request failed: \(error)")
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
