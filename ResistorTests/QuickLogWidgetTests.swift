import XCTest
import SwiftData
@testable import Resistor

/// Unit tests for the Quick-Log Widget feature, covering the parts that are
/// reachable from the app target (`@testable import Resistor`):
///
/// - `TemptationLogger.logResisted` — the shared single source of truth for
///   creating a resisted event, used by BOTH the in-app `LogViewModel` and the
///   widget's `LogResistedIntent`. (UC-W1 event shape.)
/// - The `LogViewModel.logTemptation` refactor regression — the refactor to call
///   `TemptationLogger` must not have changed in-app logging behavior.
/// - `Habit.todayEventsCount` — the count the widget displays at rest. (UC-W3.)
/// - The non-archived habit predicate the widget's `HabitEntityQuery` relies on
///   (UC-W2 / UC-W4) — exercised here against an in-memory store. The query type
///   itself lives in the widget extension target and is not reachable from the
///   app test target, so we verify the same SwiftData predicate it uses.
///
/// NOT covered here (widget-extension-only, manual on a real Home Screen):
/// `LogResistedIntent.perform()`, its App-Group-UserDefaults debounce, the
/// `HabitEntityQuery` type itself, `QuickLogProvider` state resolution, and the
/// `QuickLogWidgetView` rendering. See the manual checklist in the test report.
@MainActor
final class QuickLogWidgetTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TestHelpers.makeModelContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - TemptationLogger.logResisted (UC-W1 event shape)

    /// One call creates exactly one event with the widget/log default shape:
    /// occurredAt ~now, intensity nil, outcome "resisted", empty context tags,
    /// linked to the given habit, and persisted.
    func testLogResistedCreatesExactlyOneCorrectlyShapedEvent() throws {
        let habit = TestHelpers.makeHabit(name: "Sugar")
        context.insert(habit)
        try context.save()

        let before = Date()
        let event = TemptationLogger.logResisted(for: habit, in: context)
        let after = Date()

        // Returns the saved event.
        let saved = try XCTUnwrap(event, "logResisted should return the saved event")

        // Exactly one event exists in the store.
        let all = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(all.count, 1, "exactly one event should be persisted")

        // Correct shape.
        XCTAssertEqual(saved.outcome, "resisted")
        XCTAssertEqual(saved.outcomeEnum, .resisted)
        XCTAssertNil(saved.intensity, "intensity must be nil (user did not engage the scale)")
        XCTAssertEqual(saved.contextTags, [], "context tags must be empty")
        XCTAssertNil(saved.note)
        XCTAssertNil(saved.latitude)
        XCTAssertNil(saved.longitude)

        // Linked to the given habit.
        XCTAssertEqual(saved.habit?.id, habit.id)
        XCTAssertEqual(habit.activeEventsCount, 1, "event should be on the habit's relationship")

        // occurredAt is "now" (between the timestamps straddling the call).
        XCTAssertGreaterThanOrEqual(saved.occurredAt, before)
        XCTAssertLessThanOrEqual(saved.occurredAt, after)
    }

    /// Two deliberate calls create two distinct events (UC-W5: two urges = two
    /// events). The debounce that collapses an accidental double-fire lives in
    /// `LogResistedIntent`, not in `TemptationLogger`; the logger itself always
    /// writes when asked.
    func testLogResistedTwiceCreatesTwoEvents() throws {
        let habit = TestHelpers.makeHabit(name: "Sugar")
        context.insert(habit)
        try context.save()

        let first = TemptationLogger.logResisted(for: habit, in: context)
        let second = TemptationLogger.logResisted(for: habit, in: context)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.id, second?.id, "each call is a distinct event")

        let all = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(habit.activeEventsCount, 2)
    }

    /// Explicit context tags pass through (this is the param the in-app path uses;
    /// the widget passes the default empty array).
    func testLogResistedForwardsContextTags() throws {
        let habit = TestHelpers.makeHabit(name: "Sugar")
        context.insert(habit)
        try context.save()

        let event = TemptationLogger.logResisted(
            for: habit,
            in: context,
            contextTags: ["stressed", "alone"]
        )

        XCTAssertEqual(event?.contextTags, ["stressed", "alone"])
    }

    // MARK: - LogViewModel refactor regression (UC-W1: identical in-app event)

    /// After the refactor to call `TemptationLogger.logResisted`, an in-app log
    /// must produce an event identical in shape to a direct logger call (and to
    /// the pre-refactor behavior): one event, resisted, intensity nil, empty tags,
    /// linked to the selected habit.
    func testLogViewModelProducesSameEventShapeAsLogger() throws {
        // Habit A logged via the ViewModel.
        let habitVM = TestHelpers.makeHabit(name: "ViewModel Habit")
        context.insert(habitVM)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        let ok = vm.logTemptation()
        XCTAssertTrue(ok, "logTemptation should succeed with a selected habit")

        let vmEvent = try XCTUnwrap(vm.lastLoggedEvent)
        XCTAssertEqual(vmEvent.outcome, "resisted")
        XCTAssertEqual(vmEvent.outcomeEnum, .resisted)
        XCTAssertNil(vmEvent.intensity)
        XCTAssertEqual(vmEvent.contextTags, [])
        XCTAssertEqual(vmEvent.habit?.id, habitVM.id)

        // Direct logger call on a second habit for shape comparison.
        let habitDirect = TestHelpers.makeHabit(name: "Direct Habit")
        context.insert(habitDirect)
        try context.save()
        let directEvent = try XCTUnwrap(TemptationLogger.logResisted(for: habitDirect, in: context))

        // Same shape across both creation paths.
        XCTAssertEqual(vmEvent.outcome, directEvent.outcome)
        XCTAssertEqual(vmEvent.intensity, directEvent.intensity)
        XCTAssertEqual(vmEvent.contextTags, directEvent.contextTags)
        XCTAssertEqual(vmEvent.note, directEvent.note)
    }

    /// The in-app log persists (the event survives a fresh fetch), matching the
    /// widget's write-and-persist contract.
    func testLogViewModelEventIsPersisted() throws {
        let habit = TestHelpers.makeHabit(name: "Persisted")
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        XCTAssertTrue(vm.logTemptation())

        let all = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.outcome, "resisted")
    }

    // MARK: - Habit.todayEventsCount (UC-W3 at-rest count)

    /// The widget's at-rest count is `Habit.todayEventsCount`: events whose
    /// occurredAt falls in the current calendar day, for that habit only.
    func testTodayEventsCountMatchesInAppDefinition() throws {
        let habit = TestHelpers.makeHabit(name: "Counted")
        context.insert(habit)
        try context.save()

        // Two events today (via the same logger the widget uses).
        TemptationLogger.logResisted(for: habit, in: context)
        TemptationLogger.logResisted(for: habit, in: context)

        // One event yesterday — must NOT count toward today.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let old = TestHelpers.makeEvent(habit: habit, occurredAt: yesterday, outcome: "resisted")
        context.insert(old)
        try context.save()

        XCTAssertEqual(habit.todayEventsCount, 2, "only today's events count")
    }

    /// The count is per-habit: another habit's events do not leak into this
    /// habit's count (each placed widget is bound to exactly one habit).
    func testTodayEventsCountIsPerHabit() throws {
        let habitA = TestHelpers.makeHabit(name: "A")
        let habitB = TestHelpers.makeHabit(name: "B")
        context.insert(habitA)
        context.insert(habitB)
        try context.save()

        TemptationLogger.logResisted(for: habitA, in: context)
        TemptationLogger.logResisted(for: habitB, in: context)
        TemptationLogger.logResisted(for: habitB, in: context)

        XCTAssertEqual(habitA.todayEventsCount, 1)
        XCTAssertEqual(habitB.todayEventsCount, 2)
    }

    /// After a log, the count increments (UC-W1: count increments on reload). The
    /// widget reads `todayEventsCount` fresh on each timeline reload.
    func testTodayCountIncrementsAfterLog() throws {
        let habit = TestHelpers.makeHabit(name: "Increment")
        context.insert(habit)
        try context.save()

        XCTAssertEqual(habit.todayEventsCount, 0)
        TemptationLogger.logResisted(for: habit, in: context)
        XCTAssertEqual(habit.todayEventsCount, 1)
    }

    // MARK: - Non-archived habit predicate (UC-W2 / UC-W4)

    /// The widget's `HabitEntityQuery.suggestedEntities()` and
    /// `LogResistedIntent.perform()` both filter with `!habit.isArchived`. The
    /// query type lives in the widget extension target (not reachable here), so we
    /// verify the same SwiftData predicate against an in-memory store: archived
    /// habits are excluded, non-archived included, sorted by createdAt.
    func testNonArchivedPredicateExcludesArchivedHabits() throws {
        let active1 = TestHelpers.makeHabit(name: "Active One", createdAt: Date(timeIntervalSince1970: 100))
        let archived = TestHelpers.makeHabit(name: "Archived", isArchived: true, createdAt: Date(timeIntervalSince1970: 200))
        let active2 = TestHelpers.makeHabit(name: "Active Two", createdAt: Date(timeIntervalSince1970: 300))
        context.insert(active1)
        context.insert(archived)
        context.insert(active2)
        try context.save()

        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.map(\.name), ["Active One", "Active Two"],
                       "archived habits excluded, sorted by createdAt")
    }

    /// UC-W4: with zero non-archived habits the candidate list is empty (the
    /// widget cannot be bound). Here, every habit is archived.
    func testNonArchivedPredicateEmptyWhenAllArchived() throws {
        let a = TestHelpers.makeHabit(name: "A", isArchived: true)
        let b = TestHelpers.makeHabit(name: "B", isArchived: true)
        context.insert(a)
        context.insert(b)
        try context.save()

        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { !$0.isArchived })
        XCTAssertEqual(try context.fetch(descriptor).count, 0)
    }

    /// UC-W4: the widget's habit-resolution predicate (id match AND not archived)
    /// fails to resolve a habit that was archived after configuration — so the tap
    /// path finds no habit and does not log. This is the exact predicate
    /// `LogResistedIntent.perform()` and `QuickLogProvider` use.
    func testHabitResolutionPredicateFailsForArchivedBoundHabit() throws {
        let habit = TestHelpers.makeHabit(name: "Bound")
        context.insert(habit)
        try context.save()
        let id = habit.id

        // Initially resolvable.
        let liveDescriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.id == id && !$0.isArchived }
        )
        XCTAssertNotNil(try context.fetch(liveDescriptor).first, "live habit resolves")

        // Archive it — now the same predicate finds nothing (needs-reconfiguration).
        habit.isArchived = true
        try context.save()
        XCTAssertNil(try context.fetch(liveDescriptor).first,
                     "archived bound habit must not resolve, so a tap does not log")
    }

    /// UC-W4: a deleted bound habit likewise does not resolve, so the tap path
    /// would not write an orphan event.
    func testHabitResolutionPredicateFailsForDeletedBoundHabit() throws {
        let habit = TestHelpers.makeHabit(name: "Bound")
        context.insert(habit)
        try context.save()
        let id = habit.id

        context.delete(habit)
        try context.save()

        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.id == id && !$0.isArchived }
        )
        XCTAssertNil(try context.fetch(descriptor).first,
                     "deleted bound habit must not resolve")
    }
}
