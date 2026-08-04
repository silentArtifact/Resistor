import SwiftUI
import SwiftData
import MapKit
import Contacts
import ContactsUI

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
    @State private var nearby: [String] = []
    @State private var showContactPicker = false

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

                    Button {
                        showContactPicker = true
                    } label: {
                        Label("From Contacts", systemImage: "person.crop.circle")
                    }
                } footer: {
                    Text("Events logged within \(radiusText) of here show this name.")
                }

                if !nearby.isEmpty {
                    Section("Nearby") {
                        ForEach(nearby, id: \.self) { poi in
                            Button(poi) { name = poi }
                        }
                    }
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
            .task { await loadNearby() }
            .sheet(isPresented: $showContactPicker) {
                ContactNamePicker { picked in
                    if let picked, !picked.isEmpty { name = picked }
                    showContactPicker = false
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Businesses at the event's coordinate, offered as one-tap fills. Searched
    /// within `Place.matchRadius` because that is exactly the spread a saved
    /// place covers — a POI further out is not the place this event resolves to.
    ///
    /// Suggested, never auto-applied: at `kCLLocationAccuracyHundredMeters` a
    /// strip mall holds a dozen candidates, and a wrong POI is worse than none
    /// because it enters `PatternFinder` as a confident facet.
    private func loadNearby() async {
        guard !event.isInTransit,
              let lat = event.latitude,
              let lon = event.longitude else { return }
        let request = MKLocalPointsOfInterestRequest(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            radius: Place.matchRadius
        )
        guard let response = try? await MKLocalSearch(request: request).start() else { return }
        nearby = Self.nearbyNames(from: response.mapItems.map(\.name))
    }

    /// Deduped and capped, split out from the search so the filtering is
    /// testable without MapKit.
    static func nearbyNames(from raw: [String?], limit: Int = 6) -> [String] {
        var seen = Set<String>()
        return Array(
            raw.compactMap { $0 }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
                .prefix(limit)
        )
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

// MARK: - Contact Picker

/// Fills the name field from the address book — a place is often a person's
/// ("Mom", "Dave").
///
/// `CNContactPickerViewController` runs out of process, so this needs **no**
/// `CNContactStore` authorization, no permission prompt and no privacy-label
/// change: the delegate is handed only the one contact the user tapped. Only
/// the name string is read — `Place` stores the event's own coordinate, so no
/// postal address is touched and nothing is geocoded.
///
/// `onPick` fires for cancel too, with nil, because the picker dismisses itself
/// and SwiftUI's `isPresented` would otherwise stay true over a dismissed
/// controller — the sheet could never be opened again.
private struct ContactNamePicker: UIViewControllerRepresentable {
    let onPick: (String?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // A name is the only thing taken, so a contact without one is inert.
        picker.predicateForEnablingContact = NSPredicate(
            format: "givenName.length > 0 OR familyName.length > 0 OR organizationName.length > 0"
        )
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (String?) -> Void

        init(onPick: @escaping (String?) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName)
            onPick(name?.isEmpty == false ? name : contact.organizationName)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onPick(nil)
        }
    }
}
