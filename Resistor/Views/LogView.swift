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
    @State private var locationManager = LocationManager()
    @State private var showContextSheet = false
    @State private var contextNote: String = ""
    @State private var selectedContextTags: Set<TemptationEvent.ContextTag> = []
    @State private var showAddHabitSheet = false
    @State private var cardDragOffset: CGFloat = 0
    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    @State private var holdStartTime: Date?
    // Track whether the drag gesture triggered a hold, so onTapGesture can skip
    @State private var didHold = false
    // Pulsing glow toggle (driven by repeating animation)
    @State private var glowPulsing = false
    // Expanding ripple ring counter
    @State private var pulseRingScale: CGFloat = 1.0
    @State private var pulseRingOpacity: CGFloat = 1.0

    private var showContextPrompt: Bool {
        userSettings.first?.showContextPrompt ?? true
    }

    private func logTemptationAction(_ vm: LogViewModel) {
        selectedContextTags = []
        contextNote = ""

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        vm.logTemptation()

        if showContextPrompt {
            showContextSheet = true
        } else {
            vm.triggerConfirmation()
        }
    }

    private func startHold(_ vm: LogViewModel) {
        isHolding = true
        didHold = true
        holdProgress = 0
        holdStartTime = Date()
        vm.startContinuousHaptic()

        // Start pulsing glow animation
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            glowPulsing = true
        }

        // Use holdStartTime to compute progress each tick, avoiding stale capture
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [self] _ in
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
        withAnimation(.easeOut(duration: 0.25)) {
            glowPulsing = false
        }
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
        withAnimation(.easeOut(duration: 0.25)) {
            glowPulsing = false
        }
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
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }

            if viewModel == nil {
                let vm = LogViewModel(
                    modelContext: modelContext,
                    defaultHabitId: userSettings.first?.defaultHabitId,
                    locationManager: locationManager
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
                        defaultHabitId: userSettings.first?.defaultHabitId,
                        locationManager: locationManager
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
        let dimAmount = reduceMotion ? 0.0 : holdProgress * 0.5

        ZStack {
            VStack(spacing: 0) {
                // Habit carousel
                if vm.habits.count > 1 {
                    habitCarousel(vm)
                        .opacity(1.0 - dimAmount)
                }

                Spacer()

                // Current habit card (tap or hold to log)
                if let habit = vm.selectedHabit {
                    habitCard(habit, vm: vm)

                    Text("Tap or hold to log")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 12)
                        .opacity(1.0 - dimAmount)
                }

                Spacer()

                // Today's count
                if let habit = vm.selectedHabit {
                    Text("Today: \(habit.todayEventsCount) logged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24)
                        .opacity(1.0 - dimAmount)
                }
            }

            // Dimming vignette behind the card during hold
            if isHolding && !reduceMotion {
                Color.black
                    .opacity(dimAmount * 0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if vm.showConfirmation {
                confirmationBanner
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: vm.showConfirmation)
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
        let cardScale = reduceMotion ? 1.0 : 1.0 + (holdProgress * 0.08)
        let glowPulseIntensity: CGFloat = glowPulsing ? 1.0 : 0.5

        VStack(spacing: 16) {
            // Icon — gets its own glow during hold
            Image(systemName: habit.iconName ?? "circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(habitColor)
                .shadow(
                    color: habitColor.opacity(isHolding ? holdProgress * 0.8 : 0),
                    radius: isHolding ? 6 + holdProgress * 14 : 0
                )

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
                    // Background tint intensifies during hold
                    RoundedRectangle(cornerRadius: 20)
                        .fill(habitColor.opacity(0.1 + holdProgress * 0.2))
                )
        )
        .overlay(
            // Progress trim ring — shows exactly how far along the hold is
            RoundedRectangle(cornerRadius: 20)
                .trim(from: 0, to: holdProgress)
                .stroke(habitColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .opacity(isHolding ? 1 : 0)
        )
        .overlay(
            // Pulsing glow border — breathes via repeating animation
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    habitColor.opacity(holdProgress * glowPulseIntensity * 0.8),
                    lineWidth: 2 + holdProgress * 3
                )
                .blur(radius: 4)
                .opacity(isHolding ? 1 : 0)
        )
        // Radiating pulse ring — expands outward and fades (Hacking with Swift pattern)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .stroke(habitColor.opacity(0.4), lineWidth: 2)
                .scaleEffect(isHolding && !reduceMotion ? 1.0 + holdProgress * 0.15 : 1.0)
                .opacity(isHolding ? Double(1.0 - holdProgress) * 0.6 : 0)
        )
        // Layered shadow glow — tight inner + wide outer, pulse-modulated
        .shadow(
            color: habitColor.opacity(isHolding ? holdProgress * glowPulseIntensity * 0.5 : 0),
            radius: isHolding ? 12 + holdProgress * 16 : 0
        )
        .shadow(
            color: habitColor.opacity(isHolding ? holdProgress * glowPulseIntensity * 0.25 : 0),
            radius: isHolding ? 30 + holdProgress * 30 : 0
        )
        .scaleEffect(cardScale)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.15), value: cardScale)
        .zIndex(isHolding ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Log temptation for \(habit.name)")
        .accessibilityHint("Tap or hold to log a temptation")
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
