import AppIntents
import SwiftData

/// Lightweight, value-type representation of a `Habit` used as the selectable
/// option in the widget's Edit Widget configuration. Carries only what the
/// widget UI needs (name, color, icon) plus the stable habit `id`.
struct HabitAppEntity: AppEntity {
    let id: UUID
    let name: String
    let colorHex: String?
    let iconName: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Habit")
    }

    static var defaultQuery = HabitEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Resolves `HabitAppEntity` options for the configuration picker by reading the
/// shared App Group store. Only NON-ARCHIVED habits are offered, sorted by
/// creation date to match the app's Log carousel ordering.
struct HabitEntityQuery: EntityQuery {

    @MainActor
    private func fetchHabits(matching ids: [UUID]? = nil) -> [Habit] {
        guard let container = try? SharedModelContainer.makeContainer() else {
            return []
        }
        let context = container.mainContext

        var descriptor: FetchDescriptor<Habit>
        if let ids {
            descriptor = FetchDescriptor<Habit>(
                predicate: #Predicate { habit in
                    !habit.isArchived && ids.contains(habit.id)
                },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        } else {
            descriptor = FetchDescriptor<Habit>(
                predicate: #Predicate { !$0.isArchived },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitAppEntity] {
        fetchHabits(matching: identifiers).map { $0.asAppEntity }
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitAppEntity] {
        fetchHabits().map { $0.asAppEntity }
    }
}

extension Habit {
    var asAppEntity: HabitAppEntity {
        HabitAppEntity(
            id: id,
            name: name,
            colorHex: colorHex,
            iconName: iconName
        )
    }
}
