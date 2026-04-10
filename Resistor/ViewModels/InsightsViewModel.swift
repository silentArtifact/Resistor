import Foundation
import SwiftData
import Observation

@Observable
final class InsightsViewModel {
    private var modelContext: ModelContext

    var habits: [Habit] = []
    var selectedHabitIndex: Int = 0 {
        didSet { refreshEventsInRange() }
    }
    var selectedTimeRange: TimeRange = .week {
        didSet { refreshEventsInRange() }
    }

    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            }
        }
    }

    var selectedHabit: Habit? {
        guard !habits.isEmpty, selectedHabitIndex >= 0, selectedHabitIndex < habits.count else {
            return nil
        }
        return habits[selectedHabitIndex]
    }

    var hasData: Bool {
        guard let habit = selectedHabit else { return false }
        return !habit.safeEvents.isEmpty
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchHabits()
    }

    func fetchHabits() {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        do {
            habits = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch habits: \(error)")
            habits = []
        }
        if !habits.isEmpty && selectedHabitIndex >= habits.count {
            selectedHabitIndex = habits.count - 1  // didSet triggers refreshEventsInRange()
        } else {
            refreshEventsInRange()
        }
    }

    // MARK: - Statistics

    /// Cached events for the current range. Call `refreshEventsInRange()` when habit or time range changes.
    private(set) var cachedEventsInRange: [TemptationEvent] = []
    private(set) var cachedPreviousPeriodCount: Int = 0

    func refreshEventsInRange() {
        guard let habit = selectedHabit else {
            cachedEventsInRange = []
            cachedPreviousPeriodCount = 0
            return
        }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let days = selectedTimeRange.days
        guard let currentPeriodStart = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else {
            cachedEventsInRange = []
            cachedPreviousPeriodCount = 0
            return
        }
        cachedEventsInRange = habit.safeEvents.filter { $0.occurredAt >= currentPeriodStart }

        if let previousPeriodStart = calendar.date(byAdding: .day, value: -days, to: currentPeriodStart) {
            cachedPreviousPeriodCount = habit.safeEvents.filter { $0.occurredAt >= previousPeriodStart && $0.occurredAt < currentPeriodStart }.count
        } else {
            cachedPreviousPeriodCount = 0
        }
    }

    func eventsInRange() -> [TemptationEvent] {
        cachedEventsInRange
    }

    var totalEventsInRange: Int {
        cachedEventsInRange.count
    }

    var previousPeriodEvents: Int {
        cachedPreviousPeriodCount
    }

    var changeFromPreviousPeriod: Int {
        totalEventsInRange - previousPeriodEvents
    }

    var changePercentage: Double? {
        guard previousPeriodEvents > 0 else { return nil }
        return Double(changeFromPreviousPeriod) / Double(previousPeriodEvents) * 100
    }

    // MARK: - Daily Distribution

    func dailyDistribution() -> [(date: Date, count: Int)] {
        let events = cachedEventsInRange
        let calendar = Calendar.current

        var distribution: [Date: Int] = [:]

        // Initialize all days with 0
        for dayOffset in 0..<selectedTimeRange.days {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let startOfDay = calendar.startOfDay(for: date)
                distribution[startOfDay] = 0
            }
        }

        // Count events per day
        for event in events {
            let startOfDay = calendar.startOfDay(for: event.occurredAt)
            distribution[startOfDay, default: 0] += 1
        }

        return distribution.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: - Time of Day Distribution

    func timeOfDayDistribution() -> [(period: String, count: Int)] {
        let events = cachedEventsInRange
        var distribution: [String: Int] = [
            "Morning": 0,
            "Afternoon": 0,
            "Evening": 0,
            "Night": 0
        ]

        for event in events {
            let period = event.timeOfDayPeriod
            distribution[period, default: 0] += 1
        }

        let order = ["Morning", "Afternoon", "Evening", "Night"]
        return order.map { ($0, distribution[$0] ?? 0) }
    }

    // MARK: - Day of Week Distribution

    func dayOfWeekDistribution() -> [(day: String, count: Int)] {
        let events = cachedEventsInRange
        let calendar = Calendar.current
        let weekdaySymbols = calendar.shortWeekdaySymbols

        var distribution: [Int: Int] = [:]
        for i in 1...7 {
            distribution[i] = 0
        }

        for event in events {
            let weekday = event.dayOfWeek
            distribution[weekday, default: 0] += 1
        }

        return (1...7).map { (weekdaySymbols[$0 - 1], distribution[$0] ?? 0) }
    }

    // MARK: - Hourly Distribution

    func hourlyDistribution() -> [(hour: Int, count: Int)] {
        let events = cachedEventsInRange
        var distribution: [Int: Int] = [:]

        for hour in 0..<24 {
            distribution[hour] = 0
        }

        for event in events {
            let hour = event.hourOfDay
            distribution[hour, default: 0] += 1
        }

        return (0..<24).map { ($0, distribution[$0] ?? 0) }
    }

    // MARK: - Outcome Breakdown

    func outcomeBreakdown() -> [(outcome: TemptationEvent.Outcome, count: Int)] {
        let events = cachedEventsInRange
        var counts: [TemptationEvent.Outcome: Int] = [
            .resisted: 0,
            .gaveIn: 0,
            .unknown: 0
        ]
        for event in events {
            counts[event.outcomeEnum, default: 0] += 1
        }
        return TemptationEvent.Outcome.allCases.map { ($0, counts[$0] ?? 0) }
    }

    var resistedCount: Int {
        eventsInRange().filter { $0.outcomeEnum == .resisted }.count
    }

    var resistedPercentage: Int? {
        let total = totalEventsInRange
        guard total > 0 else { return nil }
        return Int(Double(resistedCount) / Double(total) * 100)
    }

    // MARK: - Peak Time

    var peakTimeOfDay: String? {
        let dist = timeOfDayDistribution()
        guard let peak = dist.max(by: { $0.count < $1.count }), peak.count > 0 else { return nil }
        return peak.period
    }

    var peakDayOfWeek: String? {
        let dist = dayOfWeekDistribution()
        guard let peak = dist.max(by: { $0.count < $1.count }), peak.count > 0 else { return nil }
        return peak.day
    }

    // MARK: - Intensity Trend

    func intensityTrend() -> [(date: Date, averageIntensity: Double)] {
        let events = cachedEventsInRange.filter { $0.intensity != nil }
        guard !events.isEmpty else { return [] }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.occurredAt)
        }

        return grouped.sorted { $0.key < $1.key }.map { date, dayEvents in
            let total = dayEvents.compactMap(\.intensity).reduce(0, +)
            let avg = Double(total) / Double(dayEvents.count)
            return (date, avg)
        }
    }

    var averageIntensity: Double? {
        let events = cachedEventsInRange.compactMap(\.intensity)
        guard !events.isEmpty else { return nil }
        return Double(events.reduce(0, +)) / Double(events.count)
    }

    // MARK: - Period Summaries

    func weekSummaries() -> [PeriodSummary] {
        guard let habit = selectedHabit else { return [] }
        let events = habit.safeEvents
        guard !events.isEmpty else { return [] }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: event.occurredAt)
            return calendar.date(from: components) ?? event.occurredAt
        }

        return grouped.sorted { $0.key > $1.key }.prefix(8).map { weekStart, weekEvents in
            let resisted = weekEvents.filter { $0.outcomeEnum == .resisted }.count
            let intensities = weekEvents.compactMap(\.intensity)
            let avgIntensity = intensities.isEmpty ? nil : Double(intensities.reduce(0, +)) / Double(intensities.count)
            return PeriodSummary(
                startDate: weekStart,
                totalEvents: weekEvents.count,
                resistedCount: resisted,
                averageIntensity: avgIntensity
            )
        }
    }

    func monthSummaries() -> [PeriodSummary] {
        guard let habit = selectedHabit else { return [] }
        let events = habit.safeEvents
        guard !events.isEmpty else { return [] }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            let components = calendar.dateComponents([.year, .month], from: event.occurredAt)
            return calendar.date(from: components) ?? event.occurredAt
        }

        return grouped.sorted { $0.key > $1.key }.prefix(6).map { monthStart, monthEvents in
            let resisted = monthEvents.filter { $0.outcomeEnum == .resisted }.count
            let intensities = monthEvents.compactMap(\.intensity)
            let avgIntensity = intensities.isEmpty ? nil : Double(intensities.reduce(0, +)) / Double(intensities.count)
            return PeriodSummary(
                startDate: monthStart,
                totalEvents: monthEvents.count,
                resistedCount: resisted,
                averageIntensity: avgIntensity
            )
        }
    }

    // MARK: - Location Distribution

    func locationDistribution() -> [(location: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in cachedEventsInRange {
            if let name = event.locationName, !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return [] }

        return counts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }
    }

    var topLocation: String? {
        locationDistribution().first?.location
    }
}

struct PeriodSummary: Identifiable {
    let startDate: Date
    let totalEvents: Int
    let resistedCount: Int
    let averageIntensity: Double?

    var id: Date { startDate }

    var resistedPercentage: Int? {
        guard totalEvents > 0 else { return nil }
        return Int(Double(resistedCount) / Double(totalEvents) * 100)
    }
}
