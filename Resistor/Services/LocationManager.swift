import Foundation
import CoreLocation
import Observation

protocol LocationProviding {
    var isAuthorized: Bool { get }
    @MainActor func requestCurrentLocation() async -> CLLocation?
    func reverseGeocode(latitude: Double, longitude: Double) async -> String?
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
