import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]

    @State private var viewModel: InsightsViewModel?

    /// Non-nil = the "Time of Day" card is expanded into the hourly drill-down
    /// for that period; nil = the 4-period overview. At most one at a time.
    @State private var expandedPeriod: TimeOfDayPeriod?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
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
                    // Trigger patterns. Sits *above* the range picker because it
                    // is the only card the picker does not scope — each row
                    // states its own window. Below the picker it read as though
                    // 7 Days applied to it, and directly contradicted the Peak
                    // Day / Peak Time cards it sat under.
                    triggerPatterns(vm)

                    // Time range. Lives at screen level because it scopes every
                    // card below it — it reads `cachedEventsInRange`, which all
                    // of them do. Buried inside the Daily Trend card it looked
                    // like it only controlled that one chart.
                    timeRangePicker(vm)

                    // Summary stats
                    summaryStats(vm)

                    // Outcome breakdown
                    outcomeBreakdown(vm)

                    // Daily trend chart
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

    /// The one card that reads several axes at once. Every chart below it shows
    /// a single dimension, where a combination like "Friday evenings at Home"
    /// disappears into two unremarkable bars.
    ///
    /// Deliberately carries no outcome figure. This card answers "what sets me
    /// off"; a resisted percentage answers "how am I doing", and putting the
    /// second next to the first reads as a grade on the situation rather than a
    /// description of it. Progress is visible here as a pattern thinning out.
    @ViewBuilder
    private func triggerPatterns(_ vm: InsightsViewModel) -> some View {
        let patterns = vm.cachedPatterns

        SectionCard(title: "Patterns") {
            if patterns.isEmpty {
                // Distinguishes "not enough logged yet" from "logged plenty,
                // nothing clusters" — the second is a real, useful answer. The
                // first counts up so the wait has a visible end.
                Text(vm.hasEnoughDataForPatterns
                     ? "No situation stands out yet. Temptations are spread evenly across times, days, and places."
                     : "Not enough yet — \(vm.occasionCount) of about \(PatternFinder.minimumOccasions) separate times logged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Hairlines rather than gaps: these are discrete findings in
                // rank order, and undivided they read as one paragraph of
                // wrapped text — the two-line rows make that worse, not better.
                VStack(spacing: 0) {
                    ForEach(Array(patterns.enumerated()), id: \.element.id) { index, pattern in
                        if index > 0 { Divider() }
                        NavigationLink {
                            HistoryView(habit: vm.selectedHabit, pattern: pattern)
                        } label: {
                            patternRow(pattern)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func patternRow(_ pattern: PatternFinder.Pattern) -> some View {
        let active = pattern.recent?.isActive ?? true

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // The finding is what the card exists to produce, so it is set
                // at body weight rather than under it — at .subheadline the
                // card's own title outranked its content.
                Text(pattern.summary)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 9) {
                if let recent = pattern.recent {
                    recencyTally(recent, active: active)
                }

                Text(pattern.frequencyDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pattern.summary). \(pattern.frequencyDescription)")
        .accessibilityHint("Shows the matching events")
    }

    /// One mark per slot in the pattern's recent window, oldest to newest,
    /// filled where the situation occurred.
    ///
    /// The mark count *is* the window length — eight Fridays draw eight marks —
    /// so this is the evidence itself rather than a gauge of it. It exists
    /// because the ratio alone cannot show direction, and direction is the only
    /// progress this app claims: a trigger being beaten empties from the right.
    /// A faded pattern keeps its marks but loses the accent, so the one thing
    /// colour means here stays "still live".
    private func recencyTally(_ recent: PatternFinder.Recent, active: Bool) -> some View {
        // .tint rather than a threaded-in colour: Insights inherits the user's
        // accent from the root .tint() and has no accent plumbing of its own.
        // A faded pattern drops to a neutral fill rather than a dimmer accent,
        // so the one thing colour means on this row stays "still live".
        let occurred: AnyShapeStyle = active
            ? AnyShapeStyle(.tint)
            : AnyShapeStyle(Color(.secondaryLabel))

        // 4pt marks with 3pt gaps, not 3-and-2: the point is that they can be
        // counted — eight marks *are* the eight Fridays — and tighter than this
        // they merge into a single bar. The extra width also gives the empty
        // slots enough area to register, which matters most in the case that
        // has nothing but empty slots.
        return HStack(spacing: 3) {
            ForEach(Array(recent.hits.enumerated()), id: \.offset) { _, hit in
                Capsule()
                    .fill(hit ? occurred : AnyShapeStyle(Color(.quaternaryLabel)))
                    .frame(width: 4, height: 12)
            }
        }
        // The line beside it states the same ratio in words; a run of 8 dots
        // announced individually would be noise.
        .accessibilityHidden(true)
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
                // Purely decorative: the legend directly below conveys the same
                // counts as readable text, so the bar would only add a confusing
                // empty element for VoiceOver.
                .accessibilityHidden(true)

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
                    .fill(Color(.secondarySystemGroupedBackground))
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
                        let isSelected = vm.selectedHabitIndex == index
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
                                    .fill(isSelected
                                          ? (Color(hex: habit.colorHex ?? "#007AFF") ?? .blue)
                                          : Color(.secondarySystemGroupedBackground))
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .accessibilityLabel(habit.name)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                HStack(spacing: 12) {
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
        // Fewer temptations reads as improvement (green). More is reported
        // neutrally — red is reserved for destructive actions, and coloring a
        // higher count as failure would editorialize a fact the user just logged.
        if change > 0 {
            return .secondary
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
            // A line, not bars: this is the one card reading a continuous series
            // (every day in range, zero-filled by `dailyDistribution`), so the
            // shape over time is the point. The categorical charts stay bars.
            Chart(data, id: \.date) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue)

                // Points only on the 7-day view; 30 of them reads as noise.
                if vm.selectedTimeRange == .week {
                    PointMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue)
                }
            }
            .frame(height: 200)
            // Counts are integers; let Charts pick ticks but never fractional
            // ones, and keep the baseline at 0 so a flat week still reads.
            .chartYScale(domain: 0...max(data.map(\.count).max() ?? 0, 1))
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
        let barColor = Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue

        SectionCard(
            title: timeOfDayTitle,
            accessory: expandedPeriod.map { _ in AnyView(collapseControl) }
        ) {
            if let period = expandedPeriod {
                expandedTimeOfDayChart(vm, period: period, barColor: barColor)
            } else {
                overviewTimeOfDayChart(vm, barColor: barColor)
            }
        }
    }

    private var timeOfDayTitle: String {
        if let period = expandedPeriod {
            return "Time of Day · \(period.displayName)"
        }
        return "Time of Day"
    }

    private var collapseControl: some View {
        Button {
            setExpandedPeriod(nil)
            UIAccessibility.post(notification: .announcement, argument: "Showing time-of-day overview")
        } label: {
            Image(systemName: "chevron.up.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse hourly breakdown")
        .accessibilityAddTraits(.isButton)
    }

    /// Applies an `expandedPeriod` change, animating only when Reduce Motion is off.
    private func setExpandedPeriod(_ period: TimeOfDayPeriod?) {
        if reduceMotion {
            expandedPeriod = period
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedPeriod = period
            }
        }
    }

    // MARK: Time of Day — Overview (4 periods)

    @ViewBuilder
    private func overviewTimeOfDayChart(_ vm: InsightsViewModel, barColor: Color) -> some View {
        let data = vm.timeOfDayDistribution()

        Chart(data, id: \.period) { item in
            BarMark(
                x: .value("Period", item.period),
                y: .value("Count", item.count)
            )
            .foregroundStyle(barColor)
        }
        .frame(height: 150)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geo[plotFrame].origin
                                let xPosition = value.location.x - origin.x
                                if let periodString: String = proxy.value(atX: xPosition),
                                   let period = TimeOfDayPeriod(periodString: periodString) {
                                    setExpandedPeriod(period)
                                    UIAccessibility.post(
                                        notification: .announcement,
                                        argument: "Showing hourly breakdown for \(period.displayName)"
                                    )
                                }
                            }
                    )
            }
        }
        // The bars themselves aren't natively accessible; we hide the chart and
        // expose explicit button elements below for VoiceOver.
        .accessibilityHidden(true)
        overviewAccessibilityElements(data)
    }

    /// Hidden-but-accessible buttons mirroring each overview bar, since Swift
    /// Charts bars aren't VoiceOver elements on their own.
    @ViewBuilder
    private func overviewAccessibilityElements(_ data: [(period: String, count: Int)]) -> some View {
        VStack(spacing: 0) {
            ForEach(data, id: \.period) { item in
                Color.clear
                    .frame(height: 0)
                    .accessibilityElement()
                    .accessibilityLabel("\(item.period), \(eventCountPhrase(item.count))")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Double tap to show hourly breakdown.")
                    .accessibilityAction {
                        if let period = TimeOfDayPeriod(periodString: item.period) {
                            setExpandedPeriod(period)
                            UIAccessibility.post(
                                notification: .announcement,
                                argument: "Showing hourly breakdown for \(period.displayName)"
                            )
                        }
                    }
            }
        }
        .frame(height: 0)
        .accessibilityElement(children: .contain)
    }

    // MARK: Time of Day — Expanded (hourly drill-down)

    @ViewBuilder
    private func expandedTimeOfDayChart(_ vm: InsightsViewModel, period: TimeOfDayPeriod, barColor: Color) -> some View {
        let data = vm.hourlyDistribution(for: period)
        // Ordered category strings so Charts renders Night left-to-right
        // (21,22,23,0,1,2,3,4) without re-sorting numerically.
        let orderedLabels = data.map { String($0.hour) }
        // Floor the y-domain at 0…1 so an all-zero window (e.g. Night with no
        // events in range) still renders a baseline and a "0/1" y-axis rather
        // than an empty void that reads as broken. The flat baseline is the
        // intended "all zero" answer (per spec), but it needs a frame to read
        // as a chart at all.
        let yMax = max(data.map(\.count).max() ?? 0, 1)

        Chart(data, id: \.hour) { item in
            BarMark(
                x: .value("Hour", String(item.hour)),
                y: .value("Count", item.count)
            )
            .foregroundStyle(barColor)
        }
        .chartXScale(domain: orderedLabels)
        .chartYScale(domain: 0...yMax)
        .frame(height: 150)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text("\(count)")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self), let hour = Int(label) {
                        Text(Self.axisHourLabel(hour, in: period))
                            .font(.caption2)
                    }
                }
            }
        }
        // Tapping hourly bars does nothing; expose each hour for VoiceOver only.
        .accessibilityHidden(true)
        expandedAccessibilityElements(data)
    }

    @ViewBuilder
    private func expandedAccessibilityElements(_ data: [(hour: Int, count: Int)]) -> some View {
        VStack(spacing: 0) {
            ForEach(data, id: \.hour) { item in
                Color.clear
                    .frame(height: 0)
                    .accessibilityElement()
                    .accessibilityLabel("\(Self.twelveHourClock(item.hour)), \(eventCountPhrase(item.count))")
            }
        }
        .frame(height: 0)
        .accessibilityElement(children: .contain)
    }

    /// "4 events" / "1 event" / "0 events" with correct pluralization.
    private func eventCountPhrase(_ count: Int) -> String {
        count == 1 ? "1 event" : "\(count) events"
    }

    /// 24-hour value → 12-hour clock form: 0→"12 AM", 13→"1 PM", 18→"6 PM".
    /// With `meridiem: false` the AM/PM is dropped ("1"), for axis ticks where
    /// the half hasn't changed since the previous tick.
    static func twelveHourClock(_ hour: Int, meridiem: Bool = true) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        guard meridiem else { return "\(twelve)" }
        return "\(twelve) \(hour < 12 ? "AM" : "PM")"
    }

    /// Axis tick text for the hourly drill-down. The window's first hour and any
    /// hour that crosses AM↔PM carry the meridiem ("9 PM", "12 AM"); the rest are
    /// bare ("10", "11") so Night's eight labels still fit across a phone.
    static func axisHourLabel(_ hour: Int, in period: TimeOfDayPeriod) -> String {
        let hours = period.hours
        guard let index = hours.firstIndex(of: hour) else { return twelveHourClock(hour) }
        let crossesMeridiem = index == 0 || (hours[index - 1] < 12) != (hour < 12)
        return twelveHourClock(hour, meridiem: crossesMeridiem)
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
            // The one card the time range does NOT scope — it reports whole weeks
            // and months from the habit's full history, so it says so.
            SectionCard(
                title: "Summary",
                accessory: AnyView(
                    Text("All time")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                )
            ) {
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
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Card

/// Wraps a section's content in the standard surface card used across Insights:
/// a titled block on `secondarySystemGroupedBackground` with consistent padding,
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
                .fill(Color(.secondarySystemGroupedBackground))
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
                // Floor low enough that the longest value ("Afternoon") still
                // fits a half-width card at large Dynamic Type without clipping.
                .minimumScaleFactor(0.5)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
}
