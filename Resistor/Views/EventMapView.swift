import SwiftUI
import SwiftData
import MapKit

struct EventMapView: View {
    @Query(sort: \TemptationEvent.occurredAt, order: .reverse) private var allEvents: [TemptationEvent]
    @Query(sort: \Place.createdAt) private var places: [Place]

    let habit: Habit?

    /// The Insights grouping name that was tapped, if the map was opened from a
    /// Top Locations row — the map then opens framed on that place rather than
    /// on every pin.
    var focusLocation: String? = nil

    /// The event whose spot is being named, driving the `PlaceNameSheet`.
    @State private var namingEvent: TemptationEvent?

    private var eventsWithLocation: [TemptationEvent] {
        let filtered: [TemptationEvent]
        if let habit = habit {
            filtered = allEvents.filter { $0.habit?.id == habit.id }
        } else {
            filtered = Array(allEvents)
        }
        return filtered.filter { $0.hasLocation }
    }

    var body: some View {
        Group {
            if eventsWithLocation.isEmpty {
                emptyState
            } else {
                mapContent
            }
        }
        .navigationTitle(focusLocation ?? "Event Map")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $namingEvent) { event in
            PlaceNameSheet(event: event)
        }
    }

    /// Frames the pins of `focusLocation` when the map was opened from a Top
    /// Locations row. A place is a spread of fixes, not a point — a drifting
    /// GPS or two entrances put its events tens of metres apart — so the camera
    /// fits their bounding box rather than centring on one of them.
    private var initialPosition: MapCameraPosition {
        guard let focusLocation else { return .automatic }
        let coords = eventsWithLocation
            .filter { places.groupingName(for: $0) == focusLocation }
            .compactMap { event -> CLLocationCoordinate2D? in
                guard let lat = event.latitude, let lon = event.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        guard let first = coords.first else { return .automatic }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let minLat = lats.min() ?? first.latitude, maxLat = lats.max() ?? first.latitude
        let minLon = lons.min() ?? first.longitude, maxLon = lons.max() ?? first.longitude
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            // Floor of ~500 m so a single pin isn't zoomed to the pavement,
            // and 40% headroom so edge pins don't sit under the hint bar.
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
            )
        ))
    }

    private var mapContent: some View {
        Map(initialPosition: initialPosition) {
            ForEach(eventsWithLocation) { event in
                if let lat = event.latitude, let lon = event.longitude {
                    Annotation(
                        places.displayName(for: event) ?? "",
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    ) {
                        eventPin(event)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { namingHint }
    }

    /// Pins carry no affordance of their own, so the map states the gesture.
    private var namingHint: some View {
        Text("Tap a pin to name the place.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func eventPin(_ event: TemptationEvent) -> some View {
        Button {
            namingEvent = event
        } label: {
            Circle()
                .fill(event.outcomeEnum.color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                )
                // Pins are 12pt; pad the tap target out to something a finger
                // can hit without changing what's drawn.
                .padding(12)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(places.displayName(for: event) ?? "Unnamed location")
        .accessibilityHint("Double tap to name this place.")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No location data")
                .font(.headline)

            Text("Events with location data will appear on this map.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        EventMapView(habit: nil)
            .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self, Place.self], inMemory: true)
    }
}
