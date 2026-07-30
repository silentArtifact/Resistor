import SwiftUI
import SwiftData
import MapKit

struct EventMapView: View {
    @Query(sort: \TemptationEvent.occurredAt, order: .reverse) private var allEvents: [TemptationEvent]
    @Query(sort: \Place.createdAt) private var places: [Place]

    let habit: Habit?

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
        .navigationTitle("Event Map")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $namingEvent) { event in
            PlaceNameSheet(event: event)
        }
    }

    private var mapContent: some View {
        Map {
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
