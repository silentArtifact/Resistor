import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var modelContext
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

    private var showContextPrompt: Bool {
        userSettings.first?.showContextPrompt ?? true
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
                viewModel = LogViewModel(
                    modelContext: modelContext,
                    defaultHabitId: userSettings.first?.defaultHabitId
                )
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

            // Current habit card
            if let habit = vm.selectedHabit {
                habitCard(habit, vm: vm)
            }

            Spacer()

            // Log button
            logButton(vm)

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
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vm.showConfirmation)
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
        }
    }

    @ViewBuilder
    private func habitCard(_ habit: Habit, vm: LogViewModel) -> some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: habit.iconName ?? "circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: habit.colorHex ?? "#007AFF") ?? .blue)

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
                .fill(Color(hex: habit.colorHex ?? "#007AFF")?.opacity(0.1) ?? Color.blue.opacity(0.1))
        )
        .padding(.horizontal, 24)
        .offset(x: cardDragOffset)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    cardDragOffset = value.translation.width * 0.4
                }
                .onEnded { value in
                    if value.translation.width > 50 {
                        vm.selectPreviousHabit()
                    } else if value.translation.width < -50 {
                        vm.selectNextHabit()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        cardDragOffset = 0
                    }
                }
        )
        .animation(.interactiveSpring, value: cardDragOffset)
    }

    @ViewBuilder
    private func logButton(_ vm: LogViewModel) -> some View {
        Button(action: {
            // Reset all sheet state
            selectedIntensity = nil
            selectedOutcome = nil
            selectedContextTags = []
            contextNote = ""
            shouldShowContextAfterOutcome = false

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            vm.logTemptation()
            showOutcomeSheet = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Log Temptation")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(accentColor)
            .cornerRadius(16)
        }
        .accessibilityLabel("Log temptation for \(vm.selectedHabit?.name ?? "habit")")
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
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
                .shadow(radius: 4)
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
