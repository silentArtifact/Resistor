import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]

    @State private var viewModel: InsightsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if habits.isEmpty {
                    emptyStateView
                } else if let vm = viewModel {
                    insightsContent(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Insights")
        }
        .onAppear {
            if viewModel == nil {
                viewModel = InsightsViewModel(modelContext: modelContext)
            } else {
                viewModel?.fetchHabits()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No habits to analyze")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add a habit and log some temptations to see your patterns here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    private func insightsContent(_ vm: InsightsViewModel) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Habit selector
                habitSelector(vm)

                if !vm.hasData {
                    noDataView
                } else {
                    // Summary stats
                    summaryStats(vm)

                    // Outcome breakdown
                    outcomeBreakdown(vm)

                    // Daily trend chart (with embedded time range picker)
                    dailyTrendChart(vm)

                    // Time of day distribution
                    timeOfDayChart(vm)

                    // Day of week distribution
                    dayOfWeekChart(vm)

                    // Top locations
                    topLocationsChart(vm)

                    // Intensity trend
                    intensityTrendChart(vm)

                    // Period summaries
                    periodSummaries(vm)

                    // View Map link
                    viewMapButton(vm)

                    // View History link
                    viewHistoryButton(vm)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func outcomeBreakdown(_ vm: InsightsViewModel) -> some View {
        let data = vm.outcomeBreakdown()
        let total = data.reduce(0) { $0 + $1.count }

        SectionCard(
            title: "Outcomes",
            accessory: vm.resistedPercentage.map { pct in
                AnyView(
                    Text("\(pct)% resisted")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                )
            }
        ) {
            if total > 0 {
                // Stacked bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(data.filter { $0.count > 0 }, id: \.outcome) { item in
                            Rectangle()
                                .fill(item.outcome.color)
                                .frame(width: max(geo.size.width * CGFloat(item.count) / CGFloat(total) - 2, 4))
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())

                // Legend
                HStack(alignment: .top, spacing: 12) {
                    ForEach(data, id: \.outcome) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(item.outcome.color)
                                .frame(width: 8, height: 8)
                            Text(item.outcome.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(item.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        }
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("No events in this period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func viewHistoryButton(_ vm: InsightsViewModel) -> some View {
        NavigationLink {
            HistoryView(habit: vm.selectedHabit)
        } label: {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.body)
                Text("View History")
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func habitSelector(_ vm: InsightsViewModel) -> some View {
        if vm.habits.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(vm.habits.enumerated()), id: \.element.id) { index, habit in
                        Button(action: {
                            vm.selectedHabitIndex = index
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: habit.iconName ?? "circle.fill")
                                    .font(.caption)
                                Text(habit.name)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(vm.selectedHabitIndex == index
                                          ? (Color(hex: habit.colorHex ?? "#007AFF") ?? .blue)
                                          : Color(.secondarySystemBackground))
                            )
                            .foregroundStyle(vm.selectedHabitIndex == index ? .white : .primary)
                        }
                    }
                }
            }
        }
    }

    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No data yet")
                .font(.headline)

            Text("Log some temptations to see your patterns and trends.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func summaryStats(_ vm: InsightsViewModel) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Total this period
                StatCard(
                    title: "This \(vm.selectedTimeRange == .week ? "Week" : "Month")",
                    value: "\(vm.totalEventsInRange)",
                    subtitle: "temptations"
                )

                // Change from previous
                StatCard(
                    title: "vs Previous",
                    value: changeValueString(vm),
                    subtitle: changeSubtitle(vm),
                    valueColor: changeColor(vm)
                )
            }

            if vm.peakTimeOfDay != nil || vm.peakDayOfWeek != nil {
                HStack(spacing: 12) {
                    if let peak = vm.peakTimeOfDay {
                        StatCard(
                            title: "Peak Time",
                            value: peak,
                            subtitle: "of day"
                        )
                    }

                    if let peakDay = vm.peakDayOfWeek {
                        StatCard(
                            title: "Peak Day",
                            value: peakDay,
                            subtitle: "of week"
                        )
                    }
                }
            }

            if let topLoc = vm.topLocation {
                HStack(spacing: 16) {
                    LocationStatCard(
                        title: "Top Location",
                        value: topLoc,
                        subtitle: "most frequent"
                    )
                }
            }
        }
    }

    private func changeValueString(_ vm: InsightsViewModel) -> String {
        let change = vm.changeFromPreviousPeriod
        if change > 0 {
            return "+\(change)"
        } else if change < 0 {
            return "\(change)"
        } else {
            return "0"
        }
    }

    private func changeSubtitle(_ vm: InsightsViewModel) -> String {
        if let percentage = vm.changePercentage {
            let sign = percentage > 0 ? "+" : ""
            return "\(sign)\(Int(percentage))%"
        }
        return "no change"
    }

    private func changeColor(_ vm: InsightsViewModel) -> Color {
        let change = vm.changeFromPreviousPeriod
        // For temptations, fewer is better (green), more is concerning (red)
        if change > 0 {
            return .red
        } else if change < 0 {
            return .green
        } else {
            return .primary
        }
    }

    @ViewBuilder
    private func timeRangePicker(_ vm: InsightsViewModel) -> some View {
        Picker("Time Range", selection: Binding(
            get: { vm.selectedTimeRange },
            set: { vm.selectedTimeRange = $0 }
        )) {
            ForEach(InsightsViewModel.TimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func dailyTrendChart(_ vm: InsightsViewModel) -> some View {
        let data = vm.dailyDistribution()

        SectionCard(title: "Daily Trend") {
            timeRangePicker(vm)

            Chart(data, id: \.date) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue)
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: vm.selectedTimeRange == .week ? 1 : 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
    }

    @ViewBuilder
    private func timeOfDayChart(_ vm: InsightsViewModel) -> some View {
        let data = vm.timeOfDayDistribution()

        SectionCard(title: "Time of Day") {
            Chart(data, id: \.period) { item in
                BarMark(
                    x: .value("Period", item.period),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue)
            }
            .frame(height: 150)
        }
    }

    @ViewBuilder
    private func intensityTrendChart(_ vm: InsightsViewModel) -> some View {
        let data = vm.intensityTrend()

        if !data.isEmpty {
            SectionCard(
                title: "Intensity Trend",
                accessory: vm.averageIntensity.map { avg in
                    AnyView(
                        Text("Avg \(String(format: "%.1f", avg))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    )
                }
            ) {
                Chart(data, id: \.date) { item in
                    LineMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Intensity", item.averageIntensity)
                    )
                    .foregroundStyle(Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue)

                    PointMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Intensity", item.averageIntensity)
                    )
                    .foregroundStyle(Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue)
                }
                .frame(height: 150)
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5])
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: vm.selectedTimeRange == .week ? 1 : 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
            }
        }
    }

    private static let summaryWeekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let summaryMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    @ViewBuilder
    private func periodSummaries(_ vm: InsightsViewModel) -> some View {
        let weekData = vm.weekSummaries()
        let monthData = vm.monthSummaries()

        if !weekData.isEmpty || !monthData.isEmpty {
            SectionCard(title: "Summary") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    // Column headers explain the otherwise-bare numbers.
                    GridRow {
                        Text("Period")
                        Text("Events")
                            .gridColumnAlignment(.trailing)
                        Text("Resisted")
                            .gridColumnAlignment(.trailing)
                        Text("Intensity")
                            .gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                    if !weekData.isEmpty {
                        summaryGroupHeader("By Week")
                        ForEach(weekData) { summary in
                            summaryRow(
                                label: Self.summaryWeekFormatter.string(from: summary.startDate),
                                summary: summary
                            )
                        }
                    }

                    if !monthData.isEmpty {
                        summaryGroupHeader("By Month")
                        ForEach(monthData) { summary in
                            summaryRow(
                                label: Self.summaryMonthFormatter.string(from: summary.startDate),
                                summary: summary
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summaryGroupHeader(_ text: String) -> some View {
        GridRow {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .gridCellColumns(4)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func summaryRow(label: String, summary: PeriodSummary) -> some View {
        GridRow {
            Text(label)
                .font(.subheadline)

            Text("\(summary.totalEvents)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let pct = summary.resistedPercentage {
                Text("\(pct)%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            } else {
                Text("—").font(.subheadline).foregroundStyle(.tertiary)
            }

            if let avg = summary.averageIntensity {
                Text(String(format: "%.1f", avg))
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text("—").font(.subheadline).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func dayOfWeekChart(_ vm: InsightsViewModel) -> some View {
        let data = vm.dayOfWeekDistribution()

        SectionCard(title: "Day of Week") {
            Chart(data, id: \.day) { item in
                BarMark(
                    x: .value("Day", item.day),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue)
            }
            .frame(height: 150)
        }
    }

    @ViewBuilder
    private func topLocationsChart(_ vm: InsightsViewModel) -> some View {
        let data = vm.locationDistribution()

        if !data.isEmpty {
            SectionCard(title: "Top Locations") {
                Chart(data, id: \.location) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Location", item.location)
                    )
                    .foregroundStyle(Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue)
                }
                .frame(height: CGFloat(data.count) * 40)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
            }
        }
    }

    @ViewBuilder
    private func viewMapButton(_ vm: InsightsViewModel) -> some View {
        NavigationLink {
            EventMapView(habit: vm.selectedHabit)
        } label: {
            HStack {
                Image(systemName: "map")
                    .font(.body)
                Text("View Map")
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Card

/// Wraps a section's content in the standard surface card used across Insights:
/// a titled block on `secondarySystemBackground` with consistent padding,
/// corner radius, and internal spacing. Keeps every section visually uniform.
private struct SectionCard<Content: View>: View {
    let title: String
    var accessory: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                if let accessory {
                    accessory
                }
            }
            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

/// A stat card variant that uses a smaller font for longer text values (e.g. location names).
struct LocationStatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
}
