import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @Query private var userSettings: [UserSettings]

    private var accentColor: Color {
        if let hex = userSettings.first?.accentColorHex,
           let color = Color(hex: hex) {
            return color
        }
        return .blue
    }

    @State private var viewModel: LogViewModel?
    @State private var showContextSheet = false
    @State private var showOutcomeSheet = false
    @State private var contextNote: String = ""
    @State private var selectedContextTags: Set<TemptationEvent.ContextTag> = []
    @State private var selectedOutcome: TemptationEvent.Outcome?
    @State private var selectedIntensity: Int? = nil
    @State private var shouldShowContextAfterOutcome = false
    @State private var showAddHabitSheet = false
    @State private var cardDragOffset: CGFloat = 0
    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    @State private var holdStartTime: Date?
    // Track whether the drag gesture triggered a hold, so onTapGesture can skip
    @State private var didHold = false

    private var showContextPrompt: Bool {
        userSettings.first?.showContextPrompt ?? true
    }

    private func logTemptationAction(_ vm: LogViewModel) {
        selectedIntensity = nil
        selectedOutcome = nil
        selectedContextTags = []
        contextNote = ""
        shouldShowContextAfterOutcome = false

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        vm.logTemptation()
        showOutcomeSheet = true
    }

    private func startHold(_ vm: LogViewModel) {
        isHolding = true
        didHold = true
        holdProgress = 0
        holdStartTime = Date()
        vm.startContinuousHaptic()
        // Use holdStartTime to compute progress each tick, avoiding stale capture
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] _ in
            guard let start = holdStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            let newProgress = min(CGFloat(elapsed / 3.0), 1.0) // 3 second ramp
            holdProgress = newProgress
            vm.updateHapticIntensity(Float(newProgress))
        }
    }

    private func endHold(_ vm: LogViewModel) {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        vm.stopHaptic()
        let wasHolding = isHolding
        isHolding = false
        if wasHolding {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
                holdProgress = 0
            }
            logTemptationAction(vm)
        }
    }

    private func cancelHold(_ vm: LogViewModel) {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        vm.stopHaptic()
        isHolding = false
        didHold = false
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
            holdProgress = 0
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if habits.isEmpty {
                    emptyStateView
                } else if let vm = viewModel {
                    logContentView(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Log")
        }
        .onAppear {
            if viewModel == nil {
                let vm = LogViewModel(
                    modelContext: modelContext,
                    defaultHabitId: userSettings.first?.defaultHabitId
                )
                vm.prepareHaptics()
                viewModel = vm
            } else {
                viewModel?.fetchHabits()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No habits to track")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a habit to start logging temptations.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { showAddHabitSheet = true }) {
                Label("Add Habit", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .sheet(isPresented: $showAddHabitSheet, onDismiss: {
                if viewModel == nil {
                    viewModel = LogViewModel(
                        modelContext: modelContext,
                        defaultHabitId: userSettings.first?.defaultHabitId
                    )
                } else {
                    viewModel?.fetchHabits()
                }
            }) {
                AddHabitFromLogSheet(modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private func logContentView(_ vm: LogViewModel) -> some View {
        VStack(spacing: 0) {
            // Habit carousel
            if vm.habits.count > 1 {
                habitCarousel(vm)
            }

            Spacer()

            // Current habit card (tap to log, hold to resist)
            if let habit = vm.selectedHabit {
                habitCard(habit, vm: vm)

                Text("Tap to log · Hold to resist")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }

            Spacer()

            // Today's count
            if let habit = vm.selectedHabit {
                Text("Today: \(habit.todayEventsCount) logged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .top) {
            if vm.showConfirmation {
                confirmationBanner
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: vm.showConfirmation)
        .sheet(isPresented: $showOutcomeSheet, onDismiss: {
            if shouldShowContextAfterOutcome {
                shouldShowContextAfterOutcome = false
                showContextSheet = true
            } else {
                vm.triggerConfirmation()
            }
        }) {
            outcomeSheet(vm)
        }
        .sheet(isPresented: $showContextSheet, onDismiss: {
            vm.triggerConfirmation()
        }) {
            contextSheet(vm)
        }
    }

    @ViewBuilder
    private func habitCarousel(_ vm: LogViewModel) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: { vm.selectPreviousHabit() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Previous habit")

                Spacer()

                Text("\(vm.selectedHabitIndex + 1) of \(vm.habits.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: { vm.selectNextHabit() }) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Next habit")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Habit indicators
            HStack(spacing: 8) {
                ForEach(Array(vm.habits.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(index == vm.selectedHabitIndex ? accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Habit \(vm.selectedHabitIndex + 1) of \(vm.habits.count)")
        }
    }

    @ViewBuilder
    private func habitCard(_ habit: Habit, vm: LogViewModel) -> some View {
        let habitColor = Color(hex: habit.colorHex ?? "#007AFF") ?? .blue
        let glowOpacity = 0.15 + (holdProgress * 0.45)
        let cardScale = 1.0 + (holdProgress * 0.03)

        VStack(spacing: 16) {
            // Icon
            Image(systemName: habit.iconName ?? "circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(habitColor)

            // Name
            Text(habit.name)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Description
            if let description = habit.habitDescription, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(habitColor.opacity(glowOpacity))
                )
        )
        .overlay(
            // Progress border during hold
            RoundedRectangle(cornerRadius: 20)
                .stroke(habitColor, lineWidth: 3)
                .opacity(isHolding ? Double(holdProgress) : 0)
        )
        .shadow(
            color: habitColor.opacity(isHolding ? Double(holdProgress) * 0.4 : 0),
            radius: isHolding ? 12 + (holdProgress * 12) : 0
        )
        .scaleEffect(reduceMotion ? 1.0 : cardScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Log temptation for \(habit.name)")
        .accessibilityHint("Tap to log, or press and hold to resist")
        .accessibilityAddTraits(.isButton)
        .padding(.horizontal, 24)
        .offset(x: cardDragOffset)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            // Only handle tap if the drag gesture didn't trigger a hold
            if !didHold {
                logTemptationAction(vm)
            }
            didHold = false
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let distance = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)

                    if distance > 30 {
                        // User is swiping, cancel hold and handle carousel
                        if isHolding {
                            cancelHold(vm)
                        }
                        cardDragOffset = value.translation.width * 0.4
                    } else if !isHolding && distance < 10 {
                        // Finger staying still — start hold
                        startHold(vm)
                    }
                }
                .onEnded { value in
                    let distance = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)

                    if distance > 30 {
                        // Swipe gesture ended — cancel any hold state
                        didHold = false
                        if value.translation.width > 50 {
                            vm.selectPreviousHabit()
                        } else if value.translation.width < -50 {
                            vm.selectNextHabit()
                        }
                        if reduceMotion {
                            cardDragOffset = 0
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                cardDragOffset = 0
                            }
                        }
                    } else if isHolding {
                        // Hold released — log temptation
                        endHold(vm)
                    }
                }
        )
        .onDisappear {
            // Clean up timer if view disappears mid-hold
            holdTimer?.invalidate()
            holdTimer = nil
            holdStartTime = nil
        }
        .animation(reduceMotion ? .none : .interactiveSpring, value: cardDragOffset)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.1), value: holdProgress)
    }

    private var confirmationBanner: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Logged!")
                .fontWeight(.medium)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .padding(.top, 8)
    }

    @ViewBuilder
    private func outcomeSheet(_ vm: LogViewModel) -> some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("How did it go?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top, 24)

                Text("Did you resist or give in to the temptation?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Intensity
                VStack(spacing: 8) {
                    Text("How strong was the urge?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { level in
                            Button(action: { selectedIntensity = level }) {
                                Text("\(level)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(selectedIntensity == level ? accentColor : Color.gray.opacity(0.2))
                                    )
                                    .foregroundStyle(selectedIntensity == level ? .white : .primary)
                            }
                            .accessibilityLabel("Intensity \(level) of 5")
                        }
                    }

                    HStack {
                        Text("Mild")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Overwhelming")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 16) {
                    // Resisted button
                    Button(action: {
                        selectedOutcome = .resisted
                        vm.updateEventOutcome(.resisted)
                        if let intensity = selectedIntensity {
                            vm.updateEventIntensity(intensity)
                        }
                        shouldShowContextAfterOutcome = showContextPrompt
                        showOutcomeSheet = false
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill")
                                .font(.title2)
                            Text("I Resisted")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.green)
                        .cornerRadius(14)
                    }
                    .accessibilityLabel("I Resisted")

                    // Gave in button
                    Button(action: {
                        selectedOutcome = .gaveIn
                        vm.updateEventOutcome(.gaveIn)
                        if let intensity = selectedIntensity {
                            vm.updateEventIntensity(intensity)
                        }
                        shouldShowContextAfterOutcome = showContextPrompt
                        showOutcomeSheet = false
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                            Text("I Gave In")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.orange)
                        .cornerRadius(14)
                    }
                    .accessibilityLabel("I Gave In")
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        selectedOutcome = nil
                        if let intensity = selectedIntensity {
                            vm.updateEventIntensity(intensity)
                        }
                        shouldShowContextAfterOutcome = showContextPrompt
                        showOutcomeSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func contextSheet(_ vm: LogViewModel) -> some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Add context (optional)")
                    .font(.headline)
                    .padding(.top)

                // Context tags (multi-select)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(TemptationEvent.ContextTag.allCases, id: \.self) { tag in
                        Button(action: {
                            if selectedContextTags.contains(tag) {
                                selectedContextTags.remove(tag)
                            } else {
                                selectedContextTags.insert(tag)
                            }
                        }) {
                            Text(tag.displayName)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedContextTags.contains(tag) ? accentColor : Color.gray.opacity(0.2))
                                )
                                .foregroundStyle(selectedContextTags.contains(tag) ? .white : .primary)
                        }
                        .accessibilityLabel(tag.displayName)
                        .accessibilityAddTraits(selectedContextTags.contains(tag) ? .isSelected : [])
                    }
                }
                .padding(.horizontal)

                // Note field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note (optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Add a note...", text: $contextNote, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        showContextSheet = false
                        selectedContextTags = []
                        contextNote = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let tags = selectedContextTags.map(\.rawValue)
                        vm.updateEventContext(contextTags: tags, note: contextNote)
                        showContextSheet = false
                        selectedContextTags = []
                        contextNote = ""
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Quick Add Habit Sheet (from Log empty state)

private struct AddHabitFromLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext

    @State private var name = ""
    @State private var description = ""
    @State private var selectedColor = HabitsViewModel.availableColors[0].hex
    @State private var selectedIcon = HabitsViewModel.availableIcons[0]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Habit name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(HabitsViewModel.availableColors, id: \.hex) { color in
                            Circle()
                                .fill(Color(hex: color.hex) ?? .blue)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color.hex ? 3 : 0)
                                )
                                .onTapGesture { selectedColor = color.hex }
                                .accessibilityLabel(color.name)
                                .accessibilityAddTraits(selectedColor == color.hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                        ForEach(HabitsViewModel.availableIcons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIcon == icon ? Color.blue.opacity(0.2) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedIcon == icon ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { selectedIcon = icon }
                                .accessibilityLabel(icon.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                                .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let habit = Habit(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            habitDescription: description.isEmpty ? nil : description,
                            colorHex: selectedColor,
                            iconName: selectedIcon
                        )
                        modelContext.insert(habit)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    LogView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self], inMemory: true)
}
