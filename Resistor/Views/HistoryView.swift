import SwiftUI
import SwiftData
import MapKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TemptationEvent.occurredAt, order: .reverse) private var allEvents: [TemptationEvent]

    let habit: Habit?

    private static let groupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    fileprivate static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    fileprivate static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()

    private var events: [TemptationEvent] {
        if let habit = habit {
            return allEvents.filter { $0.habit?.id == habit.id }
        }
        return allEvents
    }

    private var groupedEvents: [(String, [TemptationEvent])] {
        let calendar = Calendar.current

        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.occurredAt)
        }

        return grouped.sorted { $0.key > $1.key }
            .map { (Self.groupDateFormatter.string(from: $0.key), $0.value) }
    }

    @State private var selectedEvent: TemptationEvent?

    var body: some View {
        Group {
            if events.isEmpty {
                emptyStateView
            } else {
                eventsList
            }
        }
        .navigationTitle(habit.map { "\($0.name) History" } ?? "All History")
        .navigationBarTitleDisplayMode(.inline)
        // Item-based presentation: the sheet always has its event bound when it
        // appears, avoiding the isPresented/selectedEvent ordering race that can
        // briefly present an empty sheet.
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No events logged yet")
                .font(.headline)

            Text("Your logged temptations will appear here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var eventsList: some View {
        List {
            ForEach(groupedEvents, id: \.0) { dateString, dayEvents in
                Section(dateString) {
                    ForEach(dayEvents) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func eventRow(_ event: TemptationEvent) -> some View {
        HStack(spacing: 12) {
            // Habit icon
            if let habit = event.habit {
                Image(systemName: habit.iconName ?? "circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: habit.colorHex ?? "#007AFF") ?? .blue)
                    .frame(width: 28)
            }

            // Event details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // When the list is scoped to one habit, the screen title
                    // already names it — showing it on every row is redundant.
                    if habit == nil, let eventHabit = event.habit {
                        Text(eventHabit.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    Text(formatTime(event.occurredAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    // Outcome badge
                    outcomeLabel(event.outcome)

                    // Context tags
                    ForEach(event.contextTags, id: \.self) { tagRaw in
                        Text(TemptationEvent.displayName(for: tagRaw))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }

                    // Location badge
                    if let locName = event.locationDisplayName {
                        HStack(spacing: 2) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                            Text(locName)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                    }
                }

                // Note if present
                if let note = event.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens event details")
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEvent = event
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteEvent(event)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func outcomeLabel(_ outcome: String) -> some View {
        let parsed = TemptationEvent.Outcome(rawValue: outcome) ?? .unknown
        HStack(spacing: 4) {
            Image(systemName: parsed.iconName)
                .font(.caption2)
            Text(parsed.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(parsed.color.opacity(0.2))
        .foregroundStyle(parsed.color)
        .cornerRadius(4)
    }

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func deleteEvent(_ event: TemptationEvent) {
        modelContext.delete(event)
        try? modelContext.save()
    }
}

// MARK: - Event Detail Sheet

struct EventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let event: TemptationEvent

    private var outcomeBinding: Binding<TemptationEvent.Outcome> {
        Binding(
            get: { event.outcomeEnum },
            set: { newValue in
                event.outcome = newValue.rawValue
                try? modelContext.save()
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                // Habit section
                if let habit = event.habit {
                    Section("Habit") {
                        HStack(spacing: 12) {
                            Image(systemName: habit.iconName ?? "circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color(hex: habit.colorHex ?? "#007AFF") ?? .blue)
                            Text(habit.name)
                                .font(.body)
                        }
                    }
                }

                // Time section
                Section("When") {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(formatDate(event.occurredAt))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Time")
                        Spacer()
                        Text(formatTime(event.occurredAt))
                            .foregroundStyle(.secondary)
                    }
                }

                // Outcome section
                Section("Outcome") {
                    // "Not recorded" (unknown) is selectable only while the event is
                    // currently unknown — a recorded outcome can't be downgraded back.
                    // The current value is always present, so the Picker never warns.
                    let options: [TemptationEvent.Outcome] = event.outcomeEnum == .unknown
                        ? [.resisted, .gaveIn, .unknown]
                        : [.resisted, .gaveIn]

                    // A `.menu` Picker renders its selected value (icon + name +
                    // chevron) as the trailing control. The leading `label:` is
                    // a plain "Outcome" descriptor so the row reads
                    // "Outcome → [⊗ Gave In ⌄]": a single value, matching the
                    // icon+value rhythm of the other detail rows with no
                    // duplicated icon. The outcome is conveyed by its icon SHAPE
                    // (checkmark / xmark / questionmark) + name, so it never
                    // relies on color alone.
                    //
                    // Limitation: SwiftUI strips custom foreground colors from a
                    // `.menu` Picker's collapsed value glyph (and `.tint` only
                    // colors the chevron, not the icon), so the trailing icon
                    // renders in the default label color rather than the outcome
                    // semantic color. Carrying a colored icon in the `label:`
                    // would duplicate the glyph, which reads worse; the icon
                    // shape + name already disambiguate the outcome.
                    Picker(selection: outcomeBinding) {
                        ForEach(options, id: \.self) { o in
                            Label(o.displayName, systemImage: o.iconName)
                                .tag(o)
                        }
                    } label: {
                        Text("Outcome")
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Outcome")
                }

                // Intensity section
                if let intensity = event.intensity {
                    Section("Intensity") {
                        HStack {
                            Text("Level")
                            Spacer()
                            Text("\(intensity) of 5")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Context section
                if !event.contextTags.isEmpty {
                    Section("Context") {
                        ForEach(event.contextTags, id: \.self) { tagRaw in
                            Text(TemptationEvent.displayName(for: tagRaw))
                        }
                    }
                }

                // Location section
                if event.hasLocation {
                    Section("Location") {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.secondary)
                            Text(event.locationDisplayName ?? "Unknown")
                        }

                        if let lat = event.latitude, let lon = event.longitude {
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                latitudinalMeters: 500,
                                longitudinalMeters: 500
                            ))) {
                                Marker("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                            }
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .allowsHitTesting(false)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }

                // Note section
                if let note = event.note, !note.isEmpty {
                    Section("Note") {
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func formatDate(_ date: Date) -> String {
        HistoryView.detailDateFormatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        HistoryView.timeFormatter.string(from: date)
    }

}

#Preview {
    NavigationStack {
        HistoryView(habit: nil)
            .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
    }
}
