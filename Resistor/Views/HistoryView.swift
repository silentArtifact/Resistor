import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TemptationEvent.occurredAt, order: .reverse) private var allEvents: [TemptationEvent]

    let habit: Habit?

    private var events: [TemptationEvent] {
        if let habit = habit {
            return allEvents.filter { $0.habit?.id == habit.id }
        }
        return allEvents
    }

    private var groupedEvents: [(String, [TemptationEvent])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.occurredAt)
        }

        return grouped.sorted { $0.key > $1.key }
            .map { (formatter.string(from: $0.key), $0.value) }
    }

    @State private var selectedEvent: TemptationEvent?
    @State private var showEventDetail = false

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
        .sheet(isPresented: $showEventDetail) {
            if let event = selectedEvent {
                EventDetailSheet(event: event)
            }
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
                    if let habit = event.habit {
                        Text(habit.name)
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
                        if let tag = TemptationEvent.ContextTag(rawValue: tagRaw) {
                            Text(tag.displayName)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
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
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEvent = event
            showEventDetail = true
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func deleteEvent(_ event: TemptationEvent) {
        modelContext.delete(event)
        try? modelContext.save()
    }
}

// MARK: - Event Detail Sheet

struct EventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: TemptationEvent

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
                    HStack {
                        Image(systemName: event.outcomeEnum.iconName)
                            .foregroundStyle(event.outcomeEnum.color)
                        Text(event.outcomeEnum.displayName)
                    }
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
                            if let tag = TemptationEvent.ContextTag(rawValue: tagRaw) {
                                Text(tag.displayName)
                            }
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
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

}

#Preview {
    NavigationStack {
        HistoryView(habit: nil)
            .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self], inMemory: true)
    }
}
