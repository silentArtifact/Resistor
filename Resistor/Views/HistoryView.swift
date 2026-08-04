import SwiftUI
import SwiftData
import MapKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TemptationEvent.occurredAt, order: .reverse) private var allEvents: [TemptationEvent]
    @Query(sort: \Place.createdAt) private var places: [Place]

    let habit: Habit?
    /// When set, shows only the events that make up this pattern — the answer
    /// to "which eight Friday evenings?" that the Insights card otherwise asks
    /// the user to take on trust.
    var pattern: PatternFinder.Pattern? = nil

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
        var result = allEvents
        if let habit = habit {
            result = result.filter { $0.habit?.id == habit.id }
        }
        if let pattern {
            // Same facet extraction the finder used, so the filter cannot drift
            // from what produced the pattern.
            let wanted = Set(pattern.facets)
            result = result.filter { PatternFinder.facets(of: $0, places: places).isSuperset(of: wanted) }
        }
        return result
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
        .navigationTitle(pattern?.summary ?? habit.map { "\($0.name) History" } ?? "All History")
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

            // Event details.
            //
            // Two lines, because the row carries two kinds of fact and they
            // used to compete for one. The outcome, the habit and the time are
            // fixed — every event has exactly one of each. The circumstances
            // are a variable-length list. Racing them all in a single HStack
            // meant SwiftUI compressed whichever lost, so "Gave In" hyphenated
            // to "Gav / e In" and a place truncated to "H…" while the row next
            // to it had room for "Home".
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    outcomeLabel(event.outcome)

                    // When the list is scoped to one habit, the screen title
                    // already names it.
                    if habit == nil, let eventHabit = event.habit {
                        Text(eventHabit.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(formatTime(event.occurredAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Circumstances as one sentence rather than a run of chips.
                // Chips gave five equal-weight boxes the same visual authority
                // as the outcome, and each one truncated on its own; a single
                // line truncates once, at the end, where it costs least. The
                // glyph marks the leading item as a place, which is the only
                // distinction that mattered.
                let place = places.displayName(for: event)
                let tags = event.contextTags.map { TemptationEvent.displayName(for: $0) }
                if place != nil || !tags.isEmpty {
                    HStack(spacing: 4) {
                        if place != nil {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                        }
                        Text(([place].compactMap { $0 } + tags).joined(separator: " · "))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
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
        // The verdict is the one thing on the row that must never wrap or
        // shrink; without this it hyphenated to "Re- sist- ed".
        .lineLimit(1)
        .fixedSize()
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
    @Query(sort: \Place.createdAt) private var places: [Place]
    @Query(sort: Habit.displayOrder) private var habits: [Habit]
    @Query(sort: \ContextTag.createdAt) private var definedTags: [ContextTag]
    let event: TemptationEvent

    @State private var showPlaceNameSheet = false

    /// Active habits, plus the event's own if it has since been archived — a
    /// Picker whose selection isn't among its options warns and renders blank.
    private var habitOptions: [Habit] {
        let active = habits.filter { !$0.isArchived }
        if let current = event.habit, !active.contains(where: { $0.id == current.id }) {
            return active + [current]
        }
        return active
    }

    /// Selection by id rather than by `Habit`, so the "none" case is a plain
    /// `nil` tag instead of a doubly-optional model reference.
    private var habitBinding: Binding<UUID?> {
        Binding(
            get: { event.habit?.id },
            set: { newValue in
                event.habit = habitOptions.first { $0.id == newValue }
                try? modelContext.save()
            }
        )
    }

    /// Every tag the user could put on this event: the defined ones, plus any
    /// raw value already on the event that no longer has a `ContextTag` (a
    /// legacy enum value, or a tag deleted since it was logged) — otherwise the
    /// sheet would show a tag it gives no way to remove.
    private var tagOptions: [String] {
        let defined = definedTags.map(\.name)
        return defined + event.contextTags.filter { !defined.contains($0) }
    }

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
                // Habit section. Editable, because the common mislog is tapping
                // the wrong card on the Log screen — the event happened, it was
                // just filed against the wrong habit.
                if !habitOptions.isEmpty {
                    Section("Habit") {
                        Picker(selection: habitBinding) {
                            ForEach(habitOptions) { habit in
                                Label {
                                    Text(habit.name)
                                } icon: {
                                    Image(systemName: habit.iconName ?? "circle.fill")
                                }
                                .tag(Optional(habit.id))
                            }
                            // Only offered while the event actually has no
                            // habit, so a filed event can't be un-filed.
                            if event.habit == nil {
                                Text("None").tag(UUID?.none)
                            }
                        } label: {
                            Text("Habit")
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("Habit")
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

                // Context section. Every tag is a row that toggles, rather than
                // a list of what's set plus an editor elsewhere — context is
                // usually remembered a moment after the log, so adding one has
                // to cost the same as removing one.
                if !tagOptions.isEmpty {
                    Section("Context") {
                        ForEach(tagOptions, id: \.self) { tagRaw in
                            let isSet = event.contextTags.contains(tagRaw)
                            Button {
                                toggleTag(tagRaw)
                            } label: {
                                HStack {
                                    Text(TemptationEvent.displayName(for: tagRaw))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if isSet {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .accessibilityAddTraits(isSet ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }

                // Location section
                if event.hasLocation {
                    Section("Location") {
                        if event.isInTransit {
                            // No naming affordance: the coordinate is a road the
                            // user was passing, so a name saved here would never
                            // show on this event — the display stays "In
                            // transit" — and offering "Name" would read as broken.
                            HStack(spacing: 8) {
                                Image(systemName: "car.fill")
                                    .foregroundStyle(.secondary)
                                Text(Place.transitName)
                            }
                        } else {
                            Button {
                                showPlaceNameSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "location.fill")
                                        .foregroundStyle(.secondary)
                                    Text(places.displayName(for: event) ?? "Unknown")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(places.match(event) == nil ? "Name" : "Rename")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityHint("Double tap to name this place.")
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
            .sheet(isPresented: $showPlaceNameSheet) {
                PlaceNameSheet(event: event)
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

    private func toggleTag(_ tagRaw: String) {
        event.toggleContextTag(tagRaw)
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        HistoryView(habit: nil)
            .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self, Place.self], inMemory: true)
    }
}
