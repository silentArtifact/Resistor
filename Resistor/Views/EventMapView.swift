import SwiftUI
import SwiftData
import MapKit

struct EventMapView: View {
    @Query(sort: \TemptationEvent.occurredAt, order: .reverse) private var allEvents: [TemptationEvent]

    let habit: Habit?

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
    }

    private var mapContent: some View {
        Map {
            ForEach(eventsWithLocation) { event in
                if let lat = event.latitude, let lon = event.longitude {
                    Annotation(
                        event.locationDisplayName ?? "",
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    ) {
                        eventPin(event)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func eventPin(_ event: TemptationEvent) -> some View {
        Circle()
            .fill(event.outcomeEnum.color)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 2)
            )
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
            .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
    }
}
