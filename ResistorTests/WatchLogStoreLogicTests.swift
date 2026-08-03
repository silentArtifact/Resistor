import XCTest
import SwiftData
@testable import Resistor

/// Unit tests for the watchOS Quick-Log companion's *pure logic* (issue #49,
/// UC-WATCH-1…7), exercised against the shared SwiftData models.
///
/// `WatchLogStore` itself is compiled only into the `ResistorWatch` (watchOS)
/// target and therefore CANNOT be imported into this iOS test target — there is
/// no watch test target on this checkout, and standing one up is out of scope.
/// So, exactly as `QuickLogWidgetTests` does for the widget extension, these
/// tests re-verify the *same* resolution and counting logic the watch store
/// implements (`WatchLogStore.resolveTargetHabit`, `.activeHabits`,
/// `.todayResistedCount`) against an in-memory store. The algorithm is
/// duplicated here verbatim from the watch source; if the watch logic changes,
/// these must change with it.
///
/// NOT covered here (watch-target-only, manual on hardware): the 800ms debounce
/// in `WatchLogView.handleTap`, the `.success` Taptic haptic, the CloudKit
/// cross-device sync, and the `WatchModelContainer` CloudKit container open.
@MainActor
final class WatchLogStoreLogicTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TestHelpers.makeModelContainer()
        context = container.mainContext
        selectedHabitID = nil
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        selectedHabitID = nil
    }

    // MARK: - Mirror of WatchLogStore's private logic

    /// Verbatim copy of `WatchLogStore.activeHabits(in:)`.
    private func activeHabits() -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: Habit.displayOrder
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The habit picked on the watch this session, mirroring
    /// `WatchLogStore.selectedHabitID` (in-memory, cleared on relaunch).
    private var selectedHabitID: UUID?

    /// Verbatim copy of `WatchLogStore.resolveTargetHabit(among:)`.
    private func resolveTargetHabit() -> Habit? {
        let active = activeHabits()
        if let selectedHabitID,
           let picked = active.first(where: { $0.id == selectedHabitID }) {
            return picked
        }
        return active.first
    }

    /// Verbatim copy of `WatchLogStore.todayResistedCount(for:in:)`.
    private func todayResistedCount(for habit: Habit) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return habit.safeEvents.filter { event in
            event.outcomeEnum == .resisted &&
            calendar.isDate(event.occurredAt, inSameDayAs: today)
        }.count
    }

    // MARK: - UC-WATCH-7: target resolution (first in display order)

    /// The target is the first non-archived habit in display order — which, with
    /// no drag yet, is the earliest `createdAt`. There is no default-habit
    /// setting to prefer over it; the phone's drag order *is* the default.
    func testResolveTargetsFirstNonArchivedInDisplayOrder() throws {
        let later = TestHelpers.makeHabit(name: "Later", createdAt: Date(timeIntervalSince1970: 300))
        let earlier = TestHelpers.makeHabit(name: "Earlier", createdAt: Date(timeIntervalSince1970: 100))
        context.insert(later)
        context.insert(earlier)
        try context.save()

        let target = try XCTUnwrap(resolveTargetHabit())
        XCTAssertEqual(target.id, earlier.id, "earliest createdAt is first in display order")
    }

    /// Resolution is stable/deterministic across repeated reads (no random order).
    func testResolutionIsDeterministicAcrossReads() throws {
        for i in 0..<5 {
            context.insert(TestHelpers.makeHabit(name: "H\(i)", createdAt: Date(timeIntervalSince1970: 100)))
        }
        try context.save()

        let firstResolve = try XCTUnwrap(resolveTargetHabit()).id
        for _ in 0..<10 {
            XCTAssertEqual(try XCTUnwrap(resolveTargetHabit()).id, firstResolve,
                           "same target every read even with equal createdAt (tiebreak by id)")
        }
    }

    /// An archived habit is never the target even when it would sort first — the
    /// watch skips to the first *live* habit rather than logging to an archive.
    func testArchivedFirstHabitIsSkipped() throws {
        let archived = TestHelpers.makeHabit(name: "Archived", isArchived: true, createdAt: Date(timeIntervalSince1970: 100))
        let live = TestHelpers.makeHabit(name: "Live", createdAt: Date(timeIntervalSince1970: 200))
        context.insert(archived)
        context.insert(live)
        try context.save()

        let target = try XCTUnwrap(resolveTargetHabit())
        XCTAssertEqual(target.id, live.id, "archived habit is skipped; live habit is target")
        XCTAssertFalse(target.isArchived)
    }

    /// The resolved target always has a usable name (UC-WATCH-7: never logs to an
    /// unnamed target). Here every active habit is named, so resolution yields a
    /// named habit; a habit with empty name would not be created by the app flow.
    func testResolvedTargetIsNamed() throws {
        let h = TestHelpers.makeHabit(name: "Named Habit", createdAt: Date(timeIntervalSince1970: 100))
        context.insert(h)
        try context.save()

        let target = try XCTUnwrap(resolveTargetHabit())
        XCTAssertFalse(target.name.isEmpty, "target habit must be named")
    }

    // MARK: - Watch habit switching

    /// A habit picked on the watch beats first-in-order — the whole point of the
    /// pager is logging against something else without reaching for the phone.
    func testSelectionBeatsFirstInDisplayOrder() throws {
        let first = TestHelpers.makeHabit(name: "First", createdAt: Date(timeIntervalSince1970: 100))
        let other = TestHelpers.makeHabit(name: "Other", createdAt: Date(timeIntervalSince1970: 200))
        context.insert(first)
        context.insert(other)
        try context.save()

        XCTAssertEqual(resolveTargetHabit()?.id, first.id, "first in order before any pick")

        selectedHabitID = other.id
        XCTAssertEqual(resolveTargetHabit()?.id, other.id, "watch pick wins")
    }

    /// A picked habit that is later archived stops being the target — the watch
    /// falls back rather than logging to an archived habit.
    func testArchivedSelectionFallsBackToFirstInDisplayOrder() throws {
        let first = TestHelpers.makeHabit(name: "First", createdAt: Date(timeIntervalSince1970: 100))
        let picked = TestHelpers.makeHabit(name: "Picked", createdAt: Date(timeIntervalSince1970: 200))
        context.insert(first)
        context.insert(picked)
        try context.save()

        selectedHabitID = picked.id
        XCTAssertEqual(resolveTargetHabit()?.id, picked.id)

        picked.isArchived = true
        try context.save()

        XCTAssertEqual(resolveTargetHabit()?.id, first.id,
                       "archived pick is dropped, not logged against")
    }

    /// The picker offers exactly the loggable habits, in the phone's display
    /// order — so reordering on the phone reorders the watch list.
    func testHabitOptionsMatchPhoneDisplayOrder() throws {
        let a = TestHelpers.makeHabit(name: "A", createdAt: Date(timeIntervalSince1970: 100))
        let b = TestHelpers.makeHabit(name: "B", createdAt: Date(timeIntervalSince1970: 200))
        let archived = TestHelpers.makeHabit(name: "Archived", isArchived: true, createdAt: Date(timeIntervalSince1970: 50))
        context.insert(a)
        context.insert(b)
        context.insert(archived)
        try context.save()

        XCTAssertEqual(activeHabits().map(\.name), ["A", "B"], "archived habits are not offered")

        // Phone drag: B moved above A.
        b.sortOrder = 0
        a.sortOrder = 1
        try context.save()

        XCTAssertEqual(activeHabits().map(\.name), ["B", "A"], "watch follows the phone's order")
        XCTAssertEqual(resolveTargetHabit()?.name, "B", "and so does the fallback target")
    }

    // MARK: - UC-WATCH-5: non-loggable states resolve, never a false target

    /// No habits at all → no target resolves → state (d) noHabit (the View shows
    /// the non-loggable branch and a tap cannot log). With no default-habit
    /// setting, this is the *only* way resolution can fail.
    func testNoHabitsResolvesToNoTarget() throws {
        // Empty store.
        XCTAssertNil(resolveTargetHabit(), "no habits → no resolvable target")
    }

    /// All habits archived → no target resolves (UC-WATCH-5: habit unavailable,
    /// tap can't log).
    func testAllArchivedResolvesToNoTarget() throws {
        context.insert(TestHelpers.makeHabit(name: "A", isArchived: true))
        context.insert(TestHelpers.makeHabit(name: "B", isArchived: true))
        try context.save()

        XCTAssertNil(resolveTargetHabit(), "all archived → no resolvable target")
    }

    // MARK: - UC-WATCH-3: today's resisted count (calendar-day, resisted-only)

    /// Counts only resisted events in the current calendar day (mirrors
    /// `Habit.todayEventsCount`'s day rule, filtered to resisted).
    func testTodayResistedCountResistedOnlyToday() throws {
        let habit = TestHelpers.makeHabit(name: "Counted")
        context.insert(habit)
        try context.save()

        // Two resisted today.
        TemptationLogger.logResisted(for: habit, in: context)
        TemptationLogger.logResisted(for: habit, in: context)
        // A gave_in today — must NOT count (resisted-only).
        context.insert(TestHelpers.makeEvent(habit: habit, outcome: "gave_in"))
        // An unknown today — must NOT count.
        context.insert(TestHelpers.makeEvent(habit: habit, outcome: "unknown"))
        // A resisted yesterday — must NOT count (today-only).
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        context.insert(TestHelpers.makeEvent(habit: habit, occurredAt: yesterday, outcome: "resisted"))
        try context.save()

        XCTAssertEqual(todayResistedCount(for: habit), 2,
                       "only today's resisted events count")
    }

    /// The watch's resisted-today count never exceeds (and tracks a subset of)
    /// `Habit.todayEventsCount`: same day rule, resisted is a subset of all
    /// outcomes.
    func testResistedTodayIsSubsetOfTodayEventsCount() throws {
        let habit = TestHelpers.makeHabit(name: "Subset")
        context.insert(habit)
        try context.save()

        TemptationLogger.logResisted(for: habit, in: context)              // resisted
        context.insert(TestHelpers.makeEvent(habit: habit, outcome: "gave_in")) // not resisted
        try context.save()

        XCTAssertEqual(habit.todayEventsCount, 2, "all-outcome today count")
        XCTAssertEqual(todayResistedCount(for: habit), 1, "resisted-only today count")
        XCTAssertLessThanOrEqual(todayResistedCount(for: habit), habit.todayEventsCount)
    }

    /// Count is per-target-habit: another habit's resisted events don't leak in.
    func testResistedTodayIsPerHabit() throws {
        let a = TestHelpers.makeHabit(name: "A")
        let b = TestHelpers.makeHabit(name: "B")
        context.insert(a)
        context.insert(b)
        try context.save()

        TemptationLogger.logResisted(for: a, in: context)
        TemptationLogger.logResisted(for: b, in: context)
        TemptationLogger.logResisted(for: b, in: context)

        XCTAssertEqual(todayResistedCount(for: a), 1)
        XCTAssertEqual(todayResistedCount(for: b), 2)
    }

    /// A freshly-resolved target with no events reads 0 (a true 0, not the
    /// count-unavailable nil branch which only the watch's store-open failure
    /// produces).
    func testResistedTodayZeroForFreshHabit() throws {
        let habit = TestHelpers.makeHabit(name: "Fresh")
        context.insert(habit)
        try context.save()
        XCTAssertEqual(todayResistedCount(for: habit), 0)
    }

    // MARK: - UC-WATCH-1 / -6: one tap = one event; two taps = two events

    /// One log against the resolved target writes exactly one resisted event with
    /// the watch's event shape (intensity nil, no tags), via the shared logger.
    func testLogResolvedTargetWritesExactlyOneResistedEvent() throws {
        let habit = TestHelpers.makeHabit(name: "Tap")
        context.insert(habit)
        try context.save()

        let target = try XCTUnwrap(resolveTargetHabit())
        let event = try XCTUnwrap(TemptationLogger.logResisted(for: target, in: context))

        XCTAssertEqual(event.outcomeEnum, .resisted)
        XCTAssertNil(event.intensity, "watch log: intensity nil (user did not engage scale)")
        XCTAssertEqual(event.contextTags, [], "watch log: no context tags")
        XCTAssertEqual(event.habit?.id, habit.id)

        let all = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(todayResistedCount(for: habit), 1, "count reflects the new event")
    }

    /// Two deliberate logs = two distinct events (the 800ms debounce that
    /// collapses an accidental double-contact lives in the View, not in this data
    /// path; two real taps must both write).
    func testTwoDeliberateLogsWriteTwoEvents() throws {
        let habit = TestHelpers.makeHabit(name: "TwoTaps")
        context.insert(habit)
        try context.save()

        let target = try XCTUnwrap(resolveTargetHabit())
        let first = try XCTUnwrap(TemptationLogger.logResisted(for: target, in: context))
        let second = try XCTUnwrap(TemptationLogger.logResisted(for: target, in: context))

        XCTAssertNotEqual(first.id, second.id, "two distinct events")
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemptationEvent>()).count, 2)
        XCTAssertEqual(todayResistedCount(for: habit), 2)
    }
}
