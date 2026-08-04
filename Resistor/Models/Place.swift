import Foundation
import CoreLocation
import SwiftData

/// A user-named spot — "Home", "Work", "Grocery Store". Any event logged within
/// `matchRadius` of the coordinate displays this name instead of the coarse
/// reverse-geocoded "Neighborhood, City" string.
///
/// Places are matched by distance, not by geocoded name: at
/// `kCLLocationAccuracyHundredMeters` the home and the grocery store a mile away
/// routinely reverse-geocode to the *same* string, so aliasing that string would
/// rename both.
///
/// Duplicate names are allowed on purpose. A drifting GPS fix, or a site with two
/// entrances, is covered by saving a second `Place` with the same name — display
/// and Insights both group by name, so the two read as one place.
@Model
final class Place {
    var id: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date()

    init(name: String, latitude: Double, longitude: Double) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = Date()
    }

    /// ponytail: one fixed radius for every place, sized to the app's
    /// `kCLLocationAccuracyHundredMeters` fixes. Make it a per-place field if
    /// someone needs a campus or a mall covered.
    static let matchRadius: CLLocationDistance = 150

    /// What an event logged in a moving vehicle is called instead of a place.
    /// Not a `Place` row — nothing is saved, and no coordinate owns it.
    static let transitName = "In transit"

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Collection where Element == Place {
    /// The nearest saved place within `Place.matchRadius` of the event, if any.
    func match(_ event: TemptationEvent) -> Place? {
        guard let lat = event.latitude, let lon = event.longitude else { return nil }
        let eventLocation = CLLocation(latitude: lat, longitude: lon)
        return self
            .map { ($0, eventLocation.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { $0.1 <= Place.matchRadius }
            .min { $0.1 < $1.1 }?.0
    }

    /// What to show the user for an event's location: its saved place name, else
    /// the reverse-geocoded name, else raw coordinates.
    func displayName(for event: TemptationEvent) -> String? {
        if event.isInTransit { return Place.transitName }
        return match(event)?.name ?? event.locationDisplayName
    }

    /// Grouping key for Insights: saved place name, else the reverse-geocoded
    /// name. Raw coordinates are deliberately excluded — a lat/lon pair is not a
    /// place the user would recognize in a chart.
    func groupingName(for event: TemptationEvent) -> String? {
        // Ahead of the coordinate check below: unlike a lat/lon pair, "In
        // transit" is a name the user recognizes, so a moving event still
        // groups even when the geocode came back empty.
        if event.isInTransit { return Place.transitName }
        if let place = match(event) { return place.name }
        guard let name = event.locationName, !name.isEmpty else { return nil }
        return name
    }
}
