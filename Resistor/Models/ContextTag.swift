import Foundation
import SwiftData

@Model
final class ContextTag {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

// MARK: - Duplicate Repair

extension ContextTag {
    /// Collapses tags that share a name down to one row each.
    ///
    /// The default tags are seeded by `ContentView` whenever the list is empty,
    /// which is a per-device check racing a CloudKit import: a second device —
    /// or the same device on the launch before the import lands — sees no tags,
    /// seeds its own five, and then receives five more. The user gets every
    /// default chip twice on the Log screen.
    ///
    /// Deduplicating by **name** is lossless here, unlike `Place`, where two
    /// rows with one name are a deliberate feature. `TemptationEvent.contextTags`
    /// stores raw name strings, never tag IDs, so two `ContextTag` rows with the
    /// same name are not two tags that look alike — they are the same tag stored
    /// twice, and deleting either leaves every event that used it untouched.
    ///
    /// Survivor is the lowest `id` within each name, matching
    /// `UserSettings.mergeDuplicates`: stable, and identical on every device, so
    /// two devices repairing at once converge instead of racing.
    ///
    /// ponytail: exact name match, not case- or whitespace-insensitive. The bug
    /// is identical seeds colliding, and folding case would silently merge a
    /// "bored" the user typed on purpose into the seeded "Bored".
    @discardableResult
    static func mergeDuplicates(_ tags: [ContextTag], in context: ModelContext) -> Int {
        var keepers: [String: ContextTag] = [:]
        var doomed: [ContextTag] = []

        for tag in tags.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if keepers[tag.name] == nil {
                keepers[tag.name] = tag
            } else {
                doomed.append(tag)
            }
        }

        doomed.forEach(context.delete)
        return doomed.count
    }
}
