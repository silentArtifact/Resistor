import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @Query private var userSettings: [UserSettings]

    @State private var viewModel: LogViewModel?
    @State private var showContextSheet = false
    @State private var showOutcomeSheet = false
    @State private var contextNote: String = ""
    @State private var selectedContextTag: TemptationEvent.ContextTag?
    @State private var selectedOutcome: TemptationEvent.Outcome?

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
            viewModel = LogViewModel(modelContext: modelContext)
        }
        .onChange(of: habits.count) {
            viewModel?.fetchHabits()
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

            Text("Add a habit in the Habits tab to start logging temptations.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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
        .sheet(isPresented: $showOutcomeSheet) {
            outcomeSheet(vm)
        }
        .sheet(isPresented: $showContextSheet) {
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
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Habit indicators
            HStack(spacing: 8) {
                ForEach(Array(vm.habits.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(index == vm.selectedHabitIndex ? Color.blue : Color.gray.opacity(0.3))
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
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width > 0 {
                        vm.selectPreviousHabit()
                    } else {
                        vm.selectNextHabit()
                    }
                }
        )
    }

    @ViewBuilder
    private func logButton(_ vm: LogViewModel) -> some View {
        Button(action: {
            vm.logTemptation(showContext: showContextPrompt)
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
            .background(Color.blue)
            .cornerRadius(16)
        }
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

                VStack(spacing: 16) {
                    // Resisted button
                    Button(action: {
                        selectedOutcome = .resisted
                        vm.updateEventOutcome(.resisted)
                        showOutcomeSheet = false
                        if showContextPrompt {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showContextSheet = true
                            }
                        }
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
                        showOutcomeSheet = false
                        if showContextPrompt {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showContextSheet = true
                            }
                        }
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
                        showOutcomeSheet = false
                        selectedOutcome = nil
                        if showContextPrompt {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showContextSheet = true
                            }
                        }
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

                // Context tags
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(TemptationEvent.ContextTag.allCases, id: \.self) { tag in
                        Button(action: {
                            if selectedContextTag == tag {
                                selectedContextTag = nil
                            } else {
                                selectedContextTag = tag
                            }
                        }) {
                            Text(tag.displayName)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedContextTag == tag ? Color.blue : Color.gray.opacity(0.2))
                                )
                                .foregroundStyle(selectedContextTag == tag ? .white : .primary)
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
                        selectedContextTag = nil
                        contextNote = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.updateEventContext(contextTag: selectedContextTag, note: contextNote)
                        showContextSheet = false
                        selectedContextTag = nil
                        contextNote = ""
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    LogView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self], inMemory: true)
}
