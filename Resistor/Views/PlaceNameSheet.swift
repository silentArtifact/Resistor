import SwiftUI
import SwiftData

/// Assigns a short name to the spot where an event was logged. Saving writes a
/// `Place` at the event's coordinate; every event within `Place.matchRadius` of
/// it — past and future — then displays that name in History, on the map, and in
/// Insights' Top Locations.
struct PlaceNameSheet: View {
    let event: TemptationEvent

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Place.createdAt) private var places: [Place]

    @State private var name: String = ""
    @State private var didLoad = false

    /// The place already covering this spot. Editing renames it rather than
    /// stacking a second place on the same coordinate.
    private var existing: Place? { places.match(event) }

    /// Names already in use elsewhere, offered as one-tap fills so the same spot
    /// logged twice doesn't become "Home" and "home".
    private var suggestions: [String] {
        var seen = Set<String>()
        return places
            .map(\.name)
            .filter { !$0.isEmpty && $0 != existing?.name && seen.insert($0).inserted }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var radiusText: String {
        Measurement(value: Place.matchRadius, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    Text("Events logged within \(radiusText) of here show this name.")
                }

                if !suggestions.isEmpty {
                    Section("Saved Places") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { name = suggestion }
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("Remove Name", role: .destructive, action: remove)
                    }
                }
            }
            .navigationTitle("Name This Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                name = existing?.name ?? ""
                didLoad = true
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard !trimmedName.isEmpty,
              let lat = event.latitude,
              let lon = event.longitude else { return }

        if let existing {
            existing.name = trimmedName
        } else {
            modelContext.insert(Place(name: trimmedName, latitude: lat, longitude: lon))
        }
        try? modelContext.save()
        dismiss()
    }

    private func remove() {
        if let existing {
            modelContext.delete(existing)
            try? modelContext.save()
        }
        dismiss()
    }
}
