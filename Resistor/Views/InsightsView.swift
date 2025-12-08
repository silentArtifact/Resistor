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
            viewModel = InsightsViewModel(modelContext: modelContext)
        }
        .onChange(of: habits.count) {
            viewModel?.fetchHabits()
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

                    // Time range picker
                    timeRangePicker(vm)

                    // Daily trend chart
                    dailyTrendChart(vm)

                    // Time of day distribution
                    timeOfDayChart(vm)

                    // Day of week distribution
                    dayOfWeekChart(vm)
                }
            }
            .padding()
        }
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(vm.selectedHabitIndex == index
                                          ? (Color(hex: habit.colorHex ?? "#007AFF") ?? .blue)
                                          : Color.gray.opacity(0.2))
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
        VStack(spacing: 16) {
            HStack(spacing: 16) {
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

            if let peak = vm.peakTimeOfDay, let peakDay = vm.peakDayOfWeek {
                HStack(spacing: 16) {
                    StatCard(
                        title: "Peak Time",
                        value: peak,
                        subtitle: "of day"
                    )

                    StatCard(
                        title: "Peak Day",
                        value: peakDay,
                        subtitle: "of week"
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

        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Trend")
                .font(.headline)

            if #available(iOS 17.0, *) {
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func timeOfDayChart(_ vm: InsightsViewModel) -> some View {
        let data = vm.timeOfDayDistribution()

        VStack(alignment: .leading, spacing: 12) {
            Text("Time of Day")
                .font(.headline)

            if #available(iOS 17.0, *) {
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func dayOfWeekChart(_ vm: InsightsViewModel) -> some View {
        let data = vm.dayOfWeekDistribution()

        VStack(alignment: .leading, spacing: 12) {
            Text("Day of Week")
                .font(.headline)

            if #available(iOS 17.0, *) {
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
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(valueColor)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self], inMemory: true)
}
