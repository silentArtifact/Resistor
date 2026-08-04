import Foundation
import CoreLocation
import SwiftData

/// A contact's postal address, forward-geocoded once, so `PlaceNameSheet` can
/// offer "Mom" at the coordinate where Mom lives instead of the coffee shop
/// across the street.
///
/// **Not a `Place`, deliberately, despite the identical shape.** A `Place` is a
/// name the user confirmed, and it *applies* — it renames every event within
/// `Place.matchRadius`, retroactively, in History, on the map, in Insights and in
/// `PatternFinder`. A `ContactPlace` only *suggests*: it fills a text field the
/// user still has to save. Collapsing the two would auto-name every event logged
/// near a friend's flat.
///
/// **Device-local, never synced.** `SharedModelContainer` gives this model its
/// own store with `cloudKitDatabase: .none`, so no address leaves the phone,
/// there is no `CD_ContactPlace` record type to hand-deploy to Production, and
/// the CloudKit-only constraints (no `.unique`, defaults on everything) do not
/// bind here — the style is kept anyway so a move between configurations stays a
/// one-line change. This is a *cache* of data Contacts already syncs itself:
/// rebuildable from Settings at any time, and meaningless on a device whose
/// address book differs.
@Model
final class ContactPlace {
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
}

extension Collection where Element == ContactPlace {
    /// Names of contacts living within `Place.matchRadius` of the event, nearest
    /// first, deduplicated.
    ///
    /// Shares the radius with `Place` on purpose: it is the distance the app
    /// already treats as "the same spot", so a suggestion is offered exactly
    /// when saving it would have covered this event.
    func matches(_ event: TemptationEvent) -> [String] {
        guard !event.isInTransit,
              let lat = event.latitude,
              let lon = event.longitude else { return [] }
        let eventLocation = CLLocation(latitude: lat, longitude: lon)

        // Broken into steps with explicit types: the equivalent single chain
        // over a tuple timed the Swift solver out.
        var withinRadius: [(name: String, distance: CLLocationDistance)] = []
        for contactPlace in self where !contactPlace.name.isEmpty {
            let distance = eventLocation.distance(
                from: CLLocation(latitude: contactPlace.latitude, longitude: contactPlace.longitude)
            )
            if distance <= Place.matchRadius {
                withinRadius.append((contactPlace.name, distance))
            }
        }

        var seen = Set<String>()
        return withinRadius
            .sorted { $0.distance < $1.distance }
            .map(\.name)
            .filter { seen.insert($0).inserted }
    }
}
