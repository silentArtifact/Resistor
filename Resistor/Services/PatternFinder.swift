import Foundation

/// Finds the situations a habit's temptations cluster in — combinations of
/// time, day, place, and context that come up far more often than chance
/// would produce.
///
/// **It counts temptations, never outcomes.** Whether a given urge was
/// resisted describes how the user did; it says nothing about what provoked
/// the urge, and mixing the two turns a list of triggers into a scorecard.
/// Progress still shows up here, just in the right currency: a real trigger
/// that the user is beating thins out, and the card says so directly — "1 of
/// the last 8 Mondays" where it once read 7 of 8. That is why every row is a
/// rate over recent slots rather than a lifetime total.
///
/// The mining is association-rule mining at the smallest size that answers the
/// question: extract a few categorical facets per occasion, count every pair,
/// and compare each pair's observed share against the share independent
/// marginals predict. A pair that beats its own marginals is, by definition, a
/// pattern the charts below it on Insights cannot show — each of those reads
/// one axis at a time, so "Evening" and "Friday" both looking ordinary hides
/// that nearly every Friday evening is an event.
///
/// Three-facet patterns are found by **refining an accepted pair**, never by
/// mining triples directly. The distinction is load-bearing, and it is the
/// opposite of the intuitive one: a triple needs *less* data than a pair, not
/// more, because its expected share is the pair's times a third probability ≤ 1.
/// Mining triples directly would therefore admit exactly the small-sample
/// coincidence `binomialTail` exists to reject, over a candidate pool several
/// times larger. Refinement inherits the pair's evidence instead: the third
/// facet is added only when nearly every occasion in an already-proven cluster
/// carries it, so "Friday evenings" becomes "Friday evenings, at Home" on the
/// strength of the pair, not on a triple's lower bar.
///
/// ponytail: stops at three facets. A fourth is another refinement pass, but a
/// four-clause sentence stops being something a user can act on.
enum PatternFinder {

    /// One facet of an occasion. Time of day, weekday, and place are normally
    /// single-valued; context tags are not, which is the only reason a pair of
    /// two facets from the same dimension can occur at all.
    enum Facet: Hashable {
        case timeOfDay(String)
        case dayOfWeek(String)
        case place(String)
        case tag(String)

        var displayName: String {
            switch self {
            case .timeOfDay(let v), .dayOfWeek(let v), .place(let v): return v
            case .tag(let v): return TemptationEvent.displayName(for: v)
            }
        }

        /// Reading order — when, then where, then what — and the tie-break when
        /// two pairs describe the same occasions equally well. "Friday evenings"
        /// is a more useful sentence than "Evenings, when bored" for the same
        /// run, so the time axes sort first.
        var dimensionRank: Int {
            switch self {
            case .dayOfWeek: return 0
            case .timeOfDay: return 1
            case .place: return 2
            case .tag: return 3
            }
        }

        /// True for the facets a clock can evaluate ahead of time. Place and tag
        /// describe what an occasion turned out to be; only these two are known
        /// before the user logs, which is what the Log screen's heads-up match
        /// can rely on.
        var isCalendar: Bool {
            switch self {
            case .dayOfWeek, .timeOfDay: return true
            case .place, .tag: return false
            }
        }

        /// The `Calendar` weekday number this facet came from. Round-trips
        /// through the same localized `weekdaySymbols` array `facets(of:)` read
        /// it out of, so it cannot drift from the display name.
        var weekdayNumber: Int? {
            guard case .dayOfWeek(let name) = self else { return nil }
            return Calendar.current.weekdaySymbols.firstIndex(of: name).map { $0 + 1 }
        }
    }

    /// One sitting: every event for the habit on the same day inside the same
    /// time-of-day period.
    ///
    /// This, not the individual event, is the trial the statistics run on. Two
    /// logs forty minutes apart on a Friday evening are one occasion of being
    /// tempted, and counting them as two independent trials inflates every
    /// number here — badly, for exactly the compulsive-logging user this app
    /// exists for, who is the most likely to log four times in one bad hour.
    struct Occasion {
        let facets: Set<Facet>
        /// Earliest event in the sitting — what "when did this last happen" means.
        let date: Date
        /// Hours of the constituent events, for the "around 7 PM" readout.
        let hours: [Int]
    }

    /// How a pattern has been running lately: matches across the most recent
    /// occurrences of its calendar slot. Nil when the pattern has no day or
    /// time facet, because then there is no recurring slot to count against.
    struct Recent {
        /// One entry per slot in the window, **oldest first**, true where the
        /// situation occurred. Kept per-slot rather than pre-summed because the
        /// Insights row draws it: the ratio says how often, the sequence says
        /// whether it is thinning out, and only the second is the thing the
        /// user is working toward.
        let hits: [Bool]
        /// Pluralized slot name — "Fridays", "days".
        let unit: String

        var matched: Int { hits.filter { $0 }.count }
        var outOf: Int { hits.count }

        /// A pattern with no match in its recent window has not gone away as
        /// evidence, but it has stopped being something to prepare for.
        var isActive: Bool { matched > 0 }
    }

    struct Pattern: Identifiable {
        let facets: [Facet]
        /// Occasions matching every facet — sittings, not raw events.
        let count: Int
        /// Observed count ÷ count predicted by independent marginals. Kept as a
        /// filter only; it is never shown. "5.7× the usual rate" is a ratio
        /// against a model the user cannot see, where "4 of the last 4 Fridays"
        /// is the same fact in a currency they can act on.
        let lift: Double
        /// Probability of seeing at least this many matches by chance. Lower is
        /// stronger. Not displayed — it only filters, and breaks ties.
        let pValue: Double
        /// The hour these occasions land on, when they land tightly enough for
        /// a single hour to be honest. Nil when the cluster is spread across
        /// its period, in which case the period name is as precise as we get.
        let typicalHour: Int?
        let recent: Recent?

        /// Includes the dimension so a Place and a context tag that share a
        /// name stay distinct — otherwise two different findings collapse to
        /// one `ForEach` identity and render as the same row.
        var id: String {
            facets.map { "\($0.dimensionRank):\($0.displayName)" }.joined(separator: "|")
        }

        /// Stable internal join — "Friday · Evening · Home". Not user-facing;
        /// `summary` is. Kept because ties break on it deterministically.
        var label: String {
            facets.map(\.displayName).joined(separator: " · ")
        }

        /// The row the user reads: "Friday evenings around 7 PM, at Home".
        ///
        /// A sentence rather than a middot-joined facet list, because the facets
        /// are typed — day, time, place, context — and a template that knows the
        /// types can say the thing the user would say out loud.
        var summary: String {
            var clauses: [String] = []

            let day = facets.compactMap { facet -> String? in
                if case .dayOfWeek(let d) = facet { return d } else { return nil }
            }.first
            let period = facets.compactMap { facet -> String? in
                if case .timeOfDay(let t) = facet { return t } else { return nil }
            }.first

            // ponytail: pluralizes by appending "s". Correct for the English
            // strings this app ships; revisit with the rest of the UI if it is
            // ever localized.
            switch (day, period) {
            case let (d?, p?): clauses.append("\(d) \(p.lowercased())s")
            case let (d?, nil): clauses.append("\(d)s")
            case let (nil, p?): clauses.append("\(p)s")
            case (nil, nil): break
            }

            if let hour = typicalHour, !clauses.isEmpty {
                clauses[0] += " around \(PatternFinder.hourLabel(hour))"
            }

            for case .place(let name) in facets {
                clauses.append("at \(name)")
            }

            // Tag text is the user's own, so it is never re-cased — "when Bored"
            // is a shade awkward, but lowercasing would mangle a proper noun.
            let tags = facets.compactMap { facet -> String? in
                if case .tag = facet { return facet.displayName } else { return nil }
            }
            if !tags.isEmpty {
                clauses.append("when \(ListFormatter.localizedString(byJoining: tags))")
            }

            guard let first = clauses.first else { return label }
            return ([first.prefix(1).uppercased() + first.dropFirst()] + clauses.dropFirst())
                .joined(separator: ", ")
        }

        /// "4 of the last 4 Fridays, 11 in all" — or a plain count when the
        /// pattern has no recurring slot to measure against.
        ///
        /// One phrasing for both the screen and VoiceOver. The previous version
        /// carried "×" and "·", which had to be substituted for speech and
        /// silently lost a space doing it.
        var frequencyDescription: String {
            if let recent, recent.outOf >= 2 {
                let head = "\(recent.matched) of the last \(recent.outOf) \(recent.unit)"
                return count > recent.matched ? head + ", \(count) in all" : head
            }
            return "\(count) \(count == 1 ? "time" : "times")"
        }

        /// Biggest cluster first — the user's question is "how much of my
        /// problem is this", and significance answers a different one. A pattern
        /// that has not recurred in its recent window sinks below the live ones
        /// regardless of size; it is history, not something to prepare for. The
        /// last three keys only make ties deterministic, which matters because
        /// restatements of one cluster tie exactly and `Dictionary` iteration
        /// order is not stable across launches.
        var sortKey: (Int, Int, Double, Int, String) {
            (
                (recent?.isActive ?? true) ? 0 : 1,
                -count,
                pValue,
                facets.reduce(0) { $0 + $1.dimensionRank },
                label
            )
        }
    }

    /// Fewer separate occasions than this and every pair is noise, so report
    /// nothing. Counted in occasions rather than events on purpose: ten logs
    /// from two bad evenings is two data points, and would otherwise let a
    /// coincidence clear every floor below.
    static let minimumOccasions = 10
    /// A pattern must actually recur — two coincidences are not a pattern.
    static let minimumSupport = 3
    /// Effect-size floor. A statistically solid 1.05× is true and useless.
    static let minimumLift = 1.3
    /// Significance floor. 0.01 rather than the usual 0.05 because this screen
    /// tests dozens of candidate pairs at once, and at 0.05 roughly one in
    /// twenty would clear the bar on noise alone. A blunt nod to multiple
    /// testing — cheaper than Bonferroni and enough at this scale.
    static let maximumPValue = 0.01
    /// Share of a pattern's occasions that must be ones no accepted pattern
    /// already covers. Half — below that it is a rephrasing, not a second
    /// finding.
    static let overlapAllowance = 0.5
    /// Share of an accepted pair's occasions that must carry a third facet
    /// before it joins the sentence. High on purpose: at 0.7 the triple
    /// describes the same cluster more precisely, which is the point. Lower it
    /// and the triple becomes a sub-cluster — "Friday evenings at Home"
    /// covering half the Friday evenings understates a pattern the user
    /// already had.
    static let refinementRetention = 0.7
    static let maximumResults = 4
    /// How many past occurrences of a weekday slot the "N of the last M" line
    /// looks back over. Eight weeks is long enough to be a rate and short
    /// enough that beating a trigger visibly moves it.
    static let recentWeekdaySlots = 8
    /// Same idea for patterns with a time but no weekday.
    static let recentDaySlots = 14
    /// Share of a cluster's events that must fall in the same clock hour before
    /// the summary names it instead of just the period. Comfortably above the
    /// 25% an even spread across a four-hour period produces, and low enough
    /// that a real habit straddling the hour mark still gets named.
    static let hourAgreement = 0.6

    /// Ranked patterns, biggest first. Empty when there is too little data —
    /// which is the honest answer, not a failure.
    static func patterns(in events: [TemptationEvent], places: [Place], now: Date = Date()) -> [Pattern] {
        let occasions = occasions(of: events, places: places)
        let total = occasions.count
        guard total >= minimumOccasions else { return [] }

        var singleCounts: [Facet: Int] = [:]
        var pairCounts: [Set<Facet>: Int] = [:]
        for occasion in occasions {
            for facet in occasion.facets {
                singleCounts[facet, default: 0] += 1
            }
            for pair in unorderedPairs(of: occasion.facets) {
                pairCounts[pair, default: 0] += 1
            }
        }

        let n = Double(total)

        /// Scores a facet set shared by `matching`, or nil if it fails any
        /// floor. Both the pair pass and the refinement pass go through here, so
        /// a two-facet and a three-facet pattern are judged identically.
        func evaluate(_ facetSet: Set<Facet>, matching: Set<Int>) -> Pattern? {
            let count = matching.count
            guard count >= minimumSupport else { return nil }
            let expectedShare = facetSet.reduce(1.0) { $0 * Double(singleCounts[$1] ?? 0) / n }
            guard expectedShare > 0 else { return nil }

            let lift = Double(count) / (expectedShare * n)
            guard lift >= minimumLift else { return nil }

            // Lift alone ranks a 3-of-3 coincidence above a 12-occasion trend,
            // because a rare pair has a rare expectation to divide by. The tail
            // probability is what separates them: both are "3x expected", but
            // only one is unlikely enough to be worth telling the user about.
            let pValue = binomialTail(atLeast: count, trials: total, probability: expectedShare)
            guard pValue <= maximumPValue else { return nil }

            let matched = matching.map { occasions[$0] }
            let ordered = ordered(facetSet)
            return Pattern(
                facets: ordered,
                count: count,
                lift: lift,
                pValue: pValue,
                typicalHour: typicalHour(of: matched),
                recent: recent(for: ordered, matching: matched, since: occasions.first?.date, now: now)
            )
        }

        /// Sharpens an accepted pair into a triple when nearly every occasion in
        /// it carries the same third facet — the user gets "Friday evenings, at
        /// Home" without having to cross-reference the map themselves. Returns
        /// the original pair when no third facet is that consistent.
        func refining(_ base: Pattern, matching: Set<Int>) -> Pattern {
            let baseFacets = Set(base.facets)
            var thirdCounts: [Facet: Int] = [:]
            for index in matching {
                for facet in occasions[index].facets where !baseFacets.contains(facet) {
                    thirdCounts[facet, default: 0] += 1
                }
            }

            let floor = refinementRetention * Double(matching.count)
            return thirdCounts
                .filter { Double($0.value) >= floor }
                .compactMap { facet, _ -> Pattern? in
                    let narrowed: Set<Int> = matching.filter { occasions[$0].facets.contains(facet) }
                    return evaluate(baseFacets.union([facet]), matching: narrowed)
                }
                .min { $0.sortKey < $1.sortKey } ?? base
        }

        let candidates = pairCounts.compactMap { pair, count -> (pattern: Pattern, occasions: Set<Int>)? in
            // Cheap gate before the O(occasions) matching scan.
            guard count >= minimumSupport else { return nil }
            let matching = Set(occasions.indices.filter { pair.isSubset(of: occasions[$0].facets) })
            guard let pattern = evaluate(pair, matching: matching) else { return nil }
            return (pattern, matching)
        }
        .sorted { $0.pattern.sortKey < $1.pattern.sortKey }

        // One real cluster satisfies several pairs at once — a run of Friday
        // evenings on the phone is also "Evening · On Phone" and "Friday · On
        // Phone", all with identical counts. Listing four restatements of one
        // finding is a worse card than listing one, so take a pattern only if it
        // covers occasions the accepted ones mostly don't.
        var result: [Pattern] = []
        var covered: Set<Int> = []
        for candidate in candidates where result.count < maximumResults {
            let fresh = candidate.occasions.subtracting(covered)
            guard Double(fresh.count) >= overlapAllowance * Double(candidate.occasions.count) else { continue }
            // Refine after selection, not before: the pair earned the slot and
            // sets the ordering, and the triple only sharpens how it reads.
            result.append(refining(candidate.pattern, matching: candidate.occasions))
            covered.formUnion(candidate.occasions)
        }
        return result
    }

    /// The pattern the current moment falls inside, if any.
    ///
    /// Matched on the calendar facets alone. Place and context are part of what
    /// an occasion turns out to be — the app cannot know either before the user
    /// logs, and asking for a GPS fix to decide whether to show a line of text
    /// is not a trade worth making. A pattern with no calendar facet at all
    /// ("At Home, when bored") can never be predicted from the clock, so it
    /// never raises the heads-up.
    static func active(in patterns: [Pattern], at date: Date = Date()) -> Pattern? {
        let calendar = Calendar.current
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        let period = TemptationEvent.timeOfDayPeriod(for: date)

        return patterns.first { pattern in
            let calendarFacets = pattern.facets.filter(\.isCalendar)
            guard !calendarFacets.isEmpty else { return false }
            return calendarFacets.allSatisfy { facet in
                switch facet {
                case .dayOfWeek(let d): return d == weekday
                case .timeOfDay(let t): return t == period
                case .place, .tag: return false
                }
            }
        }
    }

    // MARK: - Occasions and facets

    /// Collapses a habit's events into sittings — same day, same time-of-day
    /// period. See `Occasion`.
    static func occasions(of events: [TemptationEvent], places: [Place]) -> [Occasion] {
        struct Key: Hashable {
            let day: Date
            let period: String
        }

        let calendar = Calendar.current
        return Dictionary(grouping: events) { event in
            Key(day: calendar.startOfDay(for: event.occurredAt), period: event.timeOfDayPeriod)
        }
        .values
        .compactMap { group -> Occasion? in
            guard let earliest = group.map(\.occurredAt).min() else { return nil }
            return Occasion(
                facets: group.reduce(into: Set<Facet>()) { $0.formUnion(facets(of: $1, places: places)) },
                date: earliest,
                hours: group.map(\.hourOfDay)
            )
        }
        .sorted { $0.date < $1.date }
    }

    static func facets(of event: TemptationEvent, places: [Place]) -> Set<Facet> {
        var result: Set<Facet> = [
            .timeOfDay(event.timeOfDayPeriod),
            .dayOfWeek(Calendar.current.weekdaySymbols[event.dayOfWeek - 1])
        ]
        if let place = places.groupingName(for: event) {
            result.insert(.place(place))
        }
        for tag in event.contextTags where !tag.isEmpty {
            result.insert(.tag(tag))
        }
        return result
    }

    private static func unorderedPairs(of facets: Set<Facet>) -> [Set<Facet>] {
        let list = Array(facets)
        guard list.count > 1 else { return [] }
        return (0..<list.count).flatMap { i in
            ((i + 1)..<list.count).map { j in Set([list[i], list[j]]) }
        }
    }

    /// Stable reading order, so the same pair always renders the same way
    /// regardless of Set iteration order.
    private static func ordered(_ pair: Set<Facet>) -> [Facet] {
        pair.sorted { ($0.dimensionRank, $0.displayName) < ($1.dimensionRank, $1.displayName) }
    }

    // MARK: - Readout

    /// The hour to name in the summary, or nil when the cluster is too spread
    /// for one to be honest. "Friday evenings around 7 PM" is a far more useful
    /// sentence than "Friday evenings" — but only if the events really are at 7.
    ///
    /// Agreement is measured on the exact hour rather than a window, because a
    /// window cannot discriminate at this scale: Evening is four hours wide, so
    /// events spread perfectly evenly across it still put 75% of themselves
    /// within ±1 of the middle. On the exact hour, that same uniform spread
    /// scores 25% and is correctly rejected.
    private static func typicalHour(of occasions: [Occasion]) -> Int? {
        let hours = occasions.flatMap(\.hours)
        guard !hours.isEmpty else { return nil }

        var counts: [Int: Int] = [:]
        for hour in hours { counts[hour, default: 0] += 1 }
        // Earlier hour wins a tie, so the summary does not flip between runs.
        guard let best = counts.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }),
              Double(best.value) >= hourAgreement * Double(hours.count)
        else { return nil }
        return best.key
    }

    /// Matches across the most recent occurrences of the pattern's calendar
    /// slot — the line that makes progress visible. A trigger the user is
    /// beating reads "1 of the last 8 Mondays" while its lifetime total keeps
    /// growing, which is the honest way round.
    private static func recent(
        for facets: [Facet],
        matching: [Occasion],
        since firstDate: Date?,
        now: Date
    ) -> Recent? {
        let calendar = Calendar.current
        guard let firstDate else { return nil }
        let firstDay = calendar.startOfDay(for: firstDate)
        let today = calendar.startOfDay(for: now)

        let slots: [Date]
        let unit: String

        if let weekday = facets.compactMap(\.weekdayNumber).first {
            let back = (calendar.component(.weekday, from: today) - weekday + 7) % 7
            guard let mostRecent = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            slots = (0..<recentWeekdaySlots).compactMap {
                calendar.date(byAdding: .weekOfYear, value: -$0, to: mostRecent)
            }
            unit = calendar.weekdaySymbols[weekday - 1] + "s"
        } else if facets.contains(where: { if case .timeOfDay = $0 { return true } else { return false } }) {
            slots = (0..<recentDaySlots).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            unit = "days"
        } else {
            // No recurring slot — "at Home, when bored" has no schedule to
            // measure against, so the row falls back to a plain count.
            return nil
        }

        let inRange = slots.filter { $0 >= firstDay }
        guard !inRange.isEmpty else { return nil }
        // `slots` is built newest-first; the tally reads left to right as time
        // passing, so reverse once here rather than at every display site.
        let hits = inRange.reversed().map { slot in
            matching.contains { calendar.isDate($0.date, inSameDayAs: slot) }
        }
        return Recent(hits: hits, unit: unit)
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        // Respects the user's 12/24-hour setting rather than hardcoding either.
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()

    static func hourLabel(_ hour: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: Date()))
        return date.map(hourFormatter.string(from:)) ?? "\(hour)"
    }

    // MARK: - Statistics

    /// P(X ≥ k) for X ~ Binomial(n, p) — the chance that a pair this frequent
    /// arose from independent marginals alone.
    ///
    /// Summed exactly from the pmf, stepping k→k+1 by a ratio rather than
    /// evaluating factorials, so nothing overflows at any count a habit log
    /// produces. A normal approximation would be shorter and wrong in exactly
    /// the regime that matters here: small counts of rare combinations.
    static func binomialTail(atLeast k: Int, trials n: Int, probability p: Double) -> Double {
        guard k > 0 else { return 1 }
        guard n > 0, p > 0 else { return 0 }
        guard p < 1 else { return k <= n ? 1 : 0 }

        var pmf = pow(1 - p, Double(n))   // P(X = 0)
        var tail = 1.0
        for i in 0..<min(k, n) {
            tail -= pmf
            pmf *= Double(n - i) / Double(i + 1) * p / (1 - p)
        }
        return min(max(tail, 0), 1)
    }
}
