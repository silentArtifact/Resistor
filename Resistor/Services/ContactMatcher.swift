import Foundation
import Contacts
import CoreLocation
import Observation
import SwiftData

/// Builds the `ContactPlace` cache: reads the address book once, forward-geocodes
/// every contact that has a postal address, and stores the coordinates so
/// `PlaceNameSheet` can suggest a person's name at their own address.
///
/// **Opt-in, and it stays opt-in.** Unlike the Maps suggestions and the contact
/// *picker* — both of which cost nothing — this needs full `CNContactStore`
/// access, changes the App Store privacy label, and runs a rate-limited network
/// geocode per contact. It buys exactly one thing over the picker: the name
/// appears without the user choosing a source. Nothing in the app depends on it,
/// and declining leaves every other suggestion working.
///
/// Rebuilds from scratch rather than reconciling. The whole set is derived, an
/// address book is small, and a moved contact would otherwise leave a row
/// pointing at where they used to live — a suggestion that is not merely stale
/// but wrong.
@MainActor
@Observable
final class ContactMatcher {

    enum Status: Equatable {
        case idle
        case working(done: Int, total: Int)
        case finished(matched: Int)
        /// Access refused, or previously refused — the prompt only ever appears
        /// once, so the app must say where to change it.
        case denied
        /// Access granted, but no contact has a postal address to geocode.
        case noAddresses
        case failed
    }

    private(set) var status: Status = .idle

    var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    /// A line of plain status for the Settings row. Nil when there is nothing to
    /// say — the row's own content already reports the resting state.
    var statusText: String? {
        switch status {
        case .idle: return nil
        case .working(let done, let total):
            return total == 0 ? "Reading contacts…" : "Matching \(done) of \(total)…"
        case .finished(let matched):
            return matched == 0 ? "No contact addresses could be located." : nil
        case .denied: return "Contacts access is off. Turn it on in Settings › Privacy › Contacts."
        case .noAddresses: return "No contacts have a postal address."
        case .failed: return "Could not read contacts."
        }
    }

    /// ponytail: one geocode a second, serially, no retry. `CLGeocoder` throttles
    /// above roughly that and a throttled request fails the same way a bad
    /// address does, so pacing is what keeps a large address book from returning
    /// mostly nothing. A skipped contact costs one suggestion and the user can
    /// re-run. Batch it if Apple ever ships a bulk API.
    private static let geocodePacing = Duration.seconds(1)

    func rebuild(in context: ModelContext) async {
        status = .working(done: 0, total: 0)

        guard await requestAccess() else {
            status = .denied
            return
        }

        let candidates: [(name: String, address: CNPostalAddress)]
        do {
            candidates = try Self.addressedContacts()
        } catch {
            print("Contact fetch failed: \(error)")
            status = .failed
            return
        }

        guard !candidates.isEmpty else {
            status = .noAddresses
            return
        }

        // Cleared up front, not at the end: a run cancelled halfway then leaves
        // a partial cache rather than the previous one plus duplicates of
        // whatever it re-geocoded.
        clear(in: context)

        let geocoder = CLGeocoder()
        var matched = 0
        for (index, candidate) in candidates.enumerated() {
            if Task.isCancelled { break }
            status = .working(done: index, total: candidates.count)
            if index > 0 { try? await Task.sleep(for: Self.geocodePacing) }

            guard let coordinate = try? await geocoder
                .geocodePostalAddress(candidate.address)
                .first?
                .location?
                .coordinate else { continue }

            context.insert(ContactPlace(
                name: candidate.name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
            matched += 1
        }

        try? context.save()
        status = .finished(matched: matched)
    }

    func clear(in context: ModelContext) {
        try? context.delete(model: ContactPlace.self)
        try? context.save()
        if case .working = status {} else { status = .idle }
    }

    // MARK: - Contacts

    private func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, error in
                if let error { print("Contacts access failed: \(error)") }
                continuation.resume(returning: granted)
            }
        }
    }

    /// Every contact carrying both a name and a postal address. The first
    /// address only — a contact with home *and* work addresses would otherwise
    /// suggest the same name at two coordinates, which reads as a bug at the one
    /// the user is not standing in.
    private static func addressedContacts() throws -> [(name: String, address: CNPostalAddress)] {
        let request = CNContactFetchRequest(keysToFetch: [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPostalAddressesKey as CNKeyDescriptor
        ])
        var found: [(name: String, address: CNPostalAddress)] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            guard let address = contact.postalAddresses.first?.value else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? contact.organizationName
            guard !name.isEmpty else { return }
            found.append((name, address))
        }
        return found
    }
}
