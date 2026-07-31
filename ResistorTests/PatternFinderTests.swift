import XCTest
import Foundation
@testable import Resistor

final class PatternFinderTests: XCTestCase {

    private let habit = TestHelpers.makeHabit()

    /// Fixed reference "now" — the Saturday after the last planted Friday, so
    /// the recent-window arithmetic is deterministic instead of drifting with
    /// the wall clock.
    private let now = Calendar.current.date(from: DateComponents(
        year: 2025, month: 3, day: 22, hour: 12
    ))!

    private func patterns(
        _ events: [TemptationEvent],
        places: [Place] = []
    ) -> [PatternFinder.Pattern] {
        PatternFinder.patterns(in: events, places: places, now: now)
    }

    /// A date on a known weekday at a known hour. 2025-01-03 is a Friday.
    private func friday(hour: Int, weekOffset: Int = 0) -> Date {
        date(year: 2025, month: 1, day: 3 + weekOffset * 7, hour: hour)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: 0
        ))!
    }

    private func event(_ when: Date, tags: [String] = [], outcome: String = "resisted") -> TemptationEvent {
        TestHelpers.makeEvent(habit: habit, occurredAt: when, outcome: outcome, contextTags: tags)
    }

    /// Background events, one per day on Tue–Thu at Morning/Afternoon hours, so
    /// each is its own occasion. Never a Friday or Monday, never Evening or
    /// Night — a cluster planted on any of those is then the only thing feeding
    /// it, and the marginals it has to beat are real.
    private func filler(_ count: Int) -> [TemptationEvent] {
        (0..<count).map { i in
            // 2025-01-07 is a Tuesday; day arithmetic keeps the weekday exact
            // across the month boundary, which DateComponents normalizes.
            event(date(
                year: 2025, month: 1,
                day: 7 + (i / 3) * 7 + (i % 3),
                hour: [8, 13][i % 2]
            ))
        }
    }

    // MARK: - Occasions

    /// The unit of evidence is a sitting, not a log. Ten taps across two bad
    /// Friday evenings is two data points; counting ten would let a pair clear
    /// every floor below on what is really a single coincidence repeated.
    func testRepeatedLogsInOneSittingCountAsOneOccasion() {
        var events: [TemptationEvent] = []
        for week in 0..<2 {
            for hour in [17, 18, 19, 20, 20] {
                events.append(event(friday(hour: hour, weekOffset: week)))
            }
        }

        XCTAssertEqual(events.count, 10)
        XCTAssertEqual(PatternFinder.occasions(of: events, places: []).count, 2)

        // And the finder refuses to call two occasions a pattern, however many
        // logs they contain.
        let found = patterns(events + filler(20))
        XCTAssertFalse(
            found.contains { $0.label.contains("Friday") && $0.label.contains("Evening") },
            "Got \(found.map(\.label))"
        )
    }

    /// Same day, different period, is two occasions — a morning urge and an
    /// evening one are separate events in the user's day.
    func testSameDayDifferentPeriodsAreSeparateOccasions() {
        let events = [8, 19].map { event(friday(hour: $0)) }
        XCTAssertEqual(PatternFinder.occasions(of: events, places: []).count, 2)
    }

    // MARK: - Noise floor

    func testTooFewOccasionsYieldsNoPatterns() {
        let events = (0..<PatternFinder.minimumOccasions - 1).map {
            event(friday(hour: 19, weekOffset: $0))
        }
        XCTAssertTrue(patterns(events).isEmpty)
    }

    func testEmptyInputYieldsNoPatterns() {
        XCTAssertTrue(patterns([]).isEmpty)
    }

    /// Every day/time equally represented — nothing should clear the floors.
    func testUniformlySpreadEventsYieldNoPatterns() {
        // 4 periods × 7 days = 28 occasions, one per cell.
        var events: [TemptationEvent] = []
        for day in 0..<7 {
            for hour in [8, 13, 19, 23] {
                events.append(event(date(year: 2025, month: 1, day: 6 + day, hour: hour)))
            }
        }
        let found = patterns(events)
        XCTAssertTrue(found.isEmpty, "Uniform data produced: \(found.map(\.label))")
    }

    // MARK: - Real pattern detection

    func testFindsPlantedDayAndTimeCombination() {
        let events = (0..<12).map { event(friday(hour: 19, weekOffset: $0)) } + filler(18)

        let top = try! XCTUnwrap(patterns(events).first)
        XCTAssertEqual(top.label, "Friday · Evening")
        XCTAssertEqual(top.count, 12)
        XCTAssertGreaterThan(top.lift, 1.5)
    }

    func testFindsTagCombination() {
        let events = (0..<10).map { event(friday(hour: 19, weekOffset: $0), tags: ["Stressed"]) }
            + filler(20)

        let labels = patterns(events).map(\.label)
        XCTAssertTrue(
            labels.contains { $0.contains("Stressed") },
            "Expected a Stressed pattern, got \(labels)"
        )
    }

    func testPatternsAreCappedAndRankedDeterministically() {
        let events = (0..<12).map {
            event(friday(hour: 19, weekOffset: $0), tags: ["Stressed", "Alone"])
        } + filler(18)

        let found = patterns(events)
        XCTAssertLessThanOrEqual(found.count, PatternFinder.maximumResults)
        for (a, b) in zip(found, found.dropFirst()) {
            XCTAssertTrue(a.sortKey < b.sortKey, "\(a.label) should sort before \(b.label)")
        }
    }

    /// Outcome is deliberately invisible to the finder. This card answers "what
    /// provokes a temptation"; whether the user then resisted is a different
    /// question, and mixing them turns a trigger list into a scorecard.
    func testOutcomeDoesNotAffectPatterns() {
        func build(_ outcome: String) -> [TemptationEvent] {
            (0..<12).map { event(friday(hour: 19, weekOffset: $0), outcome: outcome) } + filler(18)
        }

        let resisted = patterns(build("resisted"))
        let gaveIn = patterns(build("gave_in"))
        XCTAssertFalse(resisted.isEmpty)
        XCTAssertEqual(resisted.map(\.summary), gaveIn.map(\.summary))
        XCTAssertEqual(resisted.map(\.count), gaveIn.map(\.count))
    }

    /// A cluster that satisfies several pairs at once must be reported once.
    func testRestatementsOfOneClusterAreCollapsed() {
        // Every Friday-evening occasion also carries the same two tags, so
        // Friday·Evening, Evening·Stressed, Friday·Stressed, Stressed·Alone …
        // all describe the identical 12 occasions.
        let events = (0..<12).map {
            event(friday(hour: 19, weekOffset: $0), tags: ["Stressed", "Alone"])
        } + filler(18)

        let found = patterns(events)
        XCTAssertEqual(found.count, 1, "One cluster reported as: \(found.map(\.label))")
        XCTAssertEqual(found.first?.count, 12)
        // One row, and the shared tag is folded in as a refinement rather than
        // listed as a separate finding about the same 12 occasions.
        XCTAssertEqual(found.first?.label, "Friday · Evening · Alone")
    }

    // MARK: - Three-facet refinement

    func testConsistentThirdFacetSharpensThePair() {
        var events = (0..<12).map { i in
            TestHelpers.makeEvent(
                habit: habit,
                occurredAt: friday(hour: 19, weekOffset: i),
                outcome: "resisted",
                latitude: 37.7749,
                longitude: -122.4194
            )
        }
        events += filler(18)

        let home = Place(name: "Home", latitude: 37.7749, longitude: -122.4194)
        let top = try! XCTUnwrap(patterns(events, places: [home]).first)
        XCTAssertEqual(top.label, "Friday · Evening · Home")
        XCTAssertEqual(top.count, 12)
        XCTAssertEqual(top.facets.count, 3)
    }

    /// A third facet on only half the cluster is a sub-cluster. Appending it
    /// would shrink a finding the user already had rather than sharpen it.
    func testInconsistentThirdFacetIsNotAppended() {
        var events = (0..<12).map { i -> TemptationEvent in
            let atHome = i % 2 == 0
            return TestHelpers.makeEvent(
                habit: habit,
                occurredAt: friday(hour: 19, weekOffset: i),
                outcome: "resisted",
                latitude: atHome ? 37.7749 : nil,
                longitude: atHome ? -122.4194 : nil
            )
        }
        events += filler(18)

        let home = Place(name: "Home", latitude: 37.7749, longitude: -122.4194)
        let top = try! XCTUnwrap(patterns(events, places: [home]).first)
        XCTAssertEqual(top.label, "Friday · Evening")
        XCTAssertEqual(top.count, 12, "The pair keeps all its occasions")
    }

    /// Refinement must never invent a pattern the pair pass did not earn — it
    /// only relabels a slot that was already accepted.
    func testRefinementNeverAddsRows() {
        let events = (0..<12).map {
            event(friday(hour: 19, weekOffset: $0), tags: ["Stressed", "Alone", "Bored"])
        } + filler(18)

        let found = patterns(events)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.facets.count, 3, "Stops at three facets, not four")
    }

    /// Ties are broken deterministically — Dictionary order is not stable, and a
    /// card that reshuffles between launches on unchanged data reads as broken.
    func testResultsAreStableAcrossRuns() {
        let events = (0..<12).map {
            event(friday(hour: 19, weekOffset: $0), tags: ["Stressed", "Alone"])
        } + filler(18)

        let first = patterns(events).map(\.label)
        for _ in 0..<20 {
            XCTAssertEqual(patterns(events.shuffled()).map(\.label), first)
        }
    }

    // MARK: - Ranking

    /// Ranking is by size, not by significance. The user's question is "how much
    /// of my problem is this", and a p-value answers a different one: a rare
    /// pair has a rare expectation to divide by, so a 3-occasion fluke can be
    /// more *surprising* than a 12-occasion trend while mattering far less.
    func testLargePatternOutranksSmallerOne() {
        var events = (0..<3).map { event(date(year: 2025, month: 1, day: 6 + $0 * 7, hour: 23)) }
        events += (0..<12).map { event(friday(hour: 19, weekOffset: $0)) }
        events += filler(15)

        let found = patterns(events)
        XCTAssertEqual(found.first?.label, "Friday · Evening", "Got \(found.map(\.label))")
        for (a, b) in zip(found, found.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.count, b.count, "\(a.label) then \(b.label)")
        }
    }

    /// A trigger the user has stopped running into sinks below a live one, even
    /// when it is larger. It stays on the card — beating something is worth
    /// seeing — but it is history, not something to prepare for.
    func testFadedPatternRanksBelowALiveOne() {
        // 12 Friday evenings, all of them before the recent window opens.
        var events = (0..<12).map { event(friday(hour: 19, weekOffset: -12 + $0)) }
        // 6 recent Monday nights. Night, not Morning: the filler runs at
        // Morning/Afternoon hours, so a Monday-morning cluster would be
        // competing with the background rather than standing out from it.
        events += (0..<6).map { event(date(year: 2025, month: 2, day: 10 + $0 * 7, hour: 22)) }
        events += filler(18)

        let found = patterns(events)
        let live = try! XCTUnwrap(found.firstIndex { $0.label.contains("Monday") }, "Got \(found.map(\.label))")
        let faded = try! XCTUnwrap(found.firstIndex { $0.label.contains("Friday") }, "Got \(found.map(\.label))")
        XCTAssertLessThan(live, faded, "A live 6-occasion pattern must precede a dead 12-occasion one")
        XCTAssertEqual(found[faded].recent?.matched, 0)
        XCTAssertGreaterThan(found[live].recent?.matched ?? 0, 0)
    }

    // MARK: - Readout

    func testSummaryReadsAsASentence() {
        var events = (0..<12).map { i in
            TestHelpers.makeEvent(
                habit: habit,
                occurredAt: friday(hour: 19, weekOffset: i),
                outcome: "resisted",
                latitude: 37.7749,
                longitude: -122.4194
            )
        }
        events += filler(18)

        let home = Place(name: "Home", latitude: 37.7749, longitude: -122.4194)
        let top = try! XCTUnwrap(patterns(events, places: [home]).first)

        XCTAssertTrue(top.summary.hasPrefix("Friday evenings"), "Got \(top.summary)")
        XCTAssertTrue(top.summary.hasSuffix("at Home"), "Got \(top.summary)")
        XCTAssertEqual(top.typicalHour, 19)
        // Hour text is locale-formatted, so assert the hour, not the string.
        XCTAssertTrue(top.summary.contains("around"), "Got \(top.summary)")
    }

    /// A cluster spread across its whole period must not claim a specific hour.
    func testSpreadClusterNamesThePeriodNotAnHour() {
        let events = (0..<12).map {
            event(friday(hour: [17, 18, 19, 20][$0 % 4], weekOffset: $0))
        } + filler(18)

        let top = try! XCTUnwrap(patterns(events).first)
        XCTAssertNil(top.typicalHour)
        XCTAssertEqual(top.summary, "Friday evenings")
    }

    func testFrequencyDescriptionCountsRecentSlots() {
        let events = (0..<12).map { event(friday(hour: 19, weekOffset: $0)) } + filler(18)

        let top = try! XCTUnwrap(patterns(events).first)
        let recent = try! XCTUnwrap(top.recent)
        XCTAssertEqual(recent.outOf, PatternFinder.recentWeekdaySlots)
        XCTAssertEqual(recent.matched, 8, "All eight of the last eight Fridays are in the cluster")
        XCTAssertEqual(top.frequencyDescription, "8 of the last 8 Fridays, 12 in all")
    }

    /// `Recent.hits` runs oldest first, because the Insights row draws it as a
    /// left-to-right tally and a reversed array would report a trigger the user
    /// is beating as one that is getting worse — the exact inversion of the only
    /// progress claim this app makes.
    func testRecentHitsRunOldestFirst() {
        // Eight Friday evenings, all in the older half of the eight-slot
        // window: 2025-01-03 + 7 weeks is 2025-02-21, and the most recent slot
        // before `now` is 2025-03-21. So the four oldest slots hit, four newest
        // miss — a pattern visibly thinning out.
        let events = (0..<8).map { event(friday(hour: 19, weekOffset: $0)) } + filler(18)

        let top = try! XCTUnwrap(patterns(events).first)
        let recent = try! XCTUnwrap(top.recent)

        XCTAssertEqual(recent.hits, [true, true, true, true, false, false, false, false])
        XCTAssertEqual(recent.matched, 4)
        XCTAssertEqual(recent.outOf, PatternFinder.recentWeekdaySlots)
        XCTAssertTrue(recent.isActive, "Four of the last eight still counts as live")
    }

    /// A Place and a context tag that share a name are different findings and
    /// must keep different identities, or SwiftUI collapses them into one row.
    func testPlaceAndTagWithTheSameNameStayDistinct() {
        let placeFacet = PatternFinder.Facet.place("Home")
        let tagFacet = PatternFinder.Facet.tag("Home")
        let day = PatternFinder.Facet.dayOfWeek("Friday")

        let a = PatternFinder.Pattern(
            facets: [day, placeFacet], count: 5, lift: 2, pValue: 0.001,
            typicalHour: nil, recent: nil
        )
        let b = PatternFinder.Pattern(
            facets: [day, tagFacet], count: 5, lift: 2, pValue: 0.001,
            typicalHour: nil, recent: nil
        )
        XCTAssertNotEqual(a.id, b.id)
    }

    /// Tapping a row filters History by the pattern's facets. That filter is
    /// `facets(of:)` again, so it has to select exactly the occasions the
    /// pattern was built from — otherwise the row claims one number and the
    /// list it opens shows another.
    func testPatternFacetsSelectExactlyItsOwnEvents() {
        let cluster = (0..<12).map { event(friday(hour: 19, weekOffset: $0), tags: ["Bored"]) }
        let events = cluster + filler(18)

        let top = try! XCTUnwrap(patterns(events).first)
        let wanted = Set(top.facets)
        let selected = events.filter {
            PatternFinder.facets(of: $0, places: []).isSuperset(of: wanted)
        }
        XCTAssertEqual(selected.count, top.count)
        XCTAssertEqual(Set(selected.map(\.id)), Set(cluster.map(\.id)))
    }

    // MARK: - Log-screen match

    /// The heads-up matches on the clock alone. Place and context describe what
    /// an occasion turned out to be, and neither is knowable before the user
    /// logs — so a Friday-evening-at-Home pattern is active on any Friday
    /// evening, wherever the user happens to be.
    func testActiveMatchesTheClockNotThePlace() {
        var events = (0..<12).map { i in
            TestHelpers.makeEvent(
                habit: habit,
                occurredAt: friday(hour: 19, weekOffset: i),
                outcome: "resisted",
                latitude: 37.7749,
                longitude: -122.4194
            )
        }
        events += filler(18)

        let home = Place(name: "Home", latitude: 37.7749, longitude: -122.4194)
        let found = patterns(events, places: [home])
        XCTAssertEqual(found.first?.label, "Friday · Evening · Home")

        XCTAssertNotNil(PatternFinder.active(in: found, at: friday(hour: 19, weekOffset: 30)))
        XCTAssertNil(PatternFinder.active(in: found, at: friday(hour: 9, weekOffset: 30)),
                     "Friday morning is not the pattern")
        XCTAssertNil(PatternFinder.active(in: found, at: date(year: 2025, month: 1, day: 6, hour: 19)),
                     "Monday evening is not the pattern")
    }

    // MARK: - Statistics

    func testBinomialTailMatchesKnownValues() {
        // 10 fair coin flips: P(X >= 5) = 0.6230, P(X >= 10) = 1/1024.
        XCTAssertEqual(PatternFinder.binomialTail(atLeast: 5, trials: 10, probability: 0.5), 0.6230, accuracy: 0.0001)
        XCTAssertEqual(PatternFinder.binomialTail(atLeast: 10, trials: 10, probability: 0.5), 1.0 / 1024, accuracy: 1e-9)

        // Degenerate inputs stay valid probabilities.
        XCTAssertEqual(PatternFinder.binomialTail(atLeast: 0, trials: 10, probability: 0.5), 1)
        XCTAssertEqual(PatternFinder.binomialTail(atLeast: 3, trials: 0, probability: 0.5), 0)
        XCTAssertEqual(PatternFinder.binomialTail(atLeast: 3, trials: 10, probability: 0), 0)
    }

    /// Why triples are reached by refining an accepted pair rather than mined
    /// directly. A triple's expected share is its parent pair's times a third
    /// probability ≤ 1, so it clears significance at a *lower* count — 8 of 100
    /// where the pair needs 13. Mining triples outright would re-admit exactly
    /// the small-sample coincidence `binomialTail` exists to reject.
    func testTripleWouldClearAtLowerSupportThanItsParentPair() {
        let pair = 0.20 * 0.30
        let triple = pair * 0.40

        func minimumSupport(toClear share: Double, outOf n: Int) -> Int? {
            (PatternFinder.minimumSupport...n).first {
                PatternFinder.binomialTail(atLeast: $0, trials: n, probability: share) <= PatternFinder.maximumPValue
                    && Double($0) / (share * Double(n)) >= PatternFinder.minimumLift
            }
        }

        for n in [30, 50, 100, 200] {
            let pairNeeds = try! XCTUnwrap(minimumSupport(toClear: pair, outOf: n))
            let tripleNeeds = try! XCTUnwrap(minimumSupport(toClear: triple, outOf: n))
            XCTAssertLessThan(tripleNeeds, pairNeeds, "at \(n) occasions")
        }
    }

    /// The same lift is far less surprising on 3 occasions than on 30.
    func testBinomialTailFallsAsSupportGrows() {
        let tiny = PatternFinder.binomialTail(atLeast: 3, trials: 30, probability: 0.01)
        let large = PatternFinder.binomialTail(atLeast: 30, trials: 300, probability: 0.01)
        XCTAssertLessThan(large, tiny)
    }

    // MARK: - Places

    func testPlaceNameBeatsGeocodedNameInPatterns() {
        let home = Place(name: "Home", latitude: 37.7749, longitude: -122.4194)
        // Fridays at Home, but at varied hours — so the pattern is the place,
        // not a time window that would out-rank and then suppress it.
        var events = (0..<12).map { i in
            TestHelpers.makeEvent(
                habit: habit,
                occurredAt: friday(hour: [8, 13, 16, 22][i % 4], weekOffset: i),
                outcome: "resisted",
                latitude: 37.7749,
                longitude: -122.4194,
                locationName: "Mission, San Francisco"
            )
        }
        events += filler(18)

        let labels = patterns(events, places: [home]).map(\.label)
        XCTAssertTrue(labels.contains { $0.contains("Home") }, "Got \(labels)")
        XCTAssertFalse(labels.contains { $0.contains("Mission") }, "Got \(labels)")
    }
}
