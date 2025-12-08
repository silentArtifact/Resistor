import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    @State private var viewModel: HabitsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    habitsContent(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        viewModel?.prepareNewHabit()
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear {
            viewModel = HabitsViewModel(modelContext: modelContext)
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.showAddHabitSheet ?? false },
            set: { _ in viewModel?.dismissSheet() }
        )) {
            if let vm = viewModel {
                habitFormSheet(vm)
            }
        }
        .alert("Delete Habit?", isPresented: Binding(
            get: { viewModel?.showDeleteConfirmation ?? false },
            set: { _ in viewModel?.cancelDelete() }
        )) {
            Button("Cancel", role: .cancel) {
                viewModel?.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                viewModel?.deleteHabit()
            }
        } message: {
            Text("This will permanently delete this habit and all its logged events. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func habitsContent(_ vm: HabitsViewModel) -> some View {
        List {
            // Active habits
            if !vm.activeHabits.isEmpty {
                Section("Active Habits") {
                    ForEach(vm.activeHabits) { habit in
                        habitRow(habit, vm: vm)
                    }
                }
            }

            // Archived habits
            if !vm.archivedHabits.isEmpty {
                Section("Archived") {
                    ForEach(vm.archivedHabits) { habit in
                        habitRow(habit, vm: vm, isArchived: true)
                    }
                }
            }

            // Settings section
            settingsSection
        }
        .listStyle(.insetGrouped)
        .overlay {
            if vm.habits.isEmpty {
                emptyHabitsView(vm)
            }
        }
    }

    @ViewBuilder
    private func habitRow(_ habit: Habit, vm: HabitsViewModel, isArchived: Bool = false) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: habit.iconName ?? "circle.fill")
                .font(.title2)
                .foregroundStyle(Color(hex: habit.colorHex ?? "#007AFF") ?? .blue)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let description = habit.habitDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Count
            VStack(alignment: .trailing) {
                Text("\(habit.events.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("total")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            vm.prepareEditHabit(habit)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                vm.confirmDelete(habit)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            if isArchived {
                Button {
                    vm.unarchiveHabit(habit)
                } label: {
                    Label("Unarchive", systemImage: "arrow.up.bin")
                }
                .tint(.blue)
            } else {
                Button {
                    vm.archiveHabit(habit)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.orange)
            }
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        Section("Settings") {
            // Context prompt toggle
            if let settings = userSettings.first {
                Toggle("Show context prompt after logging", isOn: Binding(
                    get: { settings.showContextPrompt },
                    set: { newValue in
                        settings.showContextPrompt = newValue
                        try? modelContext.save()
                    }
                ))
            }
        }
    }

    @ViewBuilder
    private func emptyHabitsView(_ vm: HabitsViewModel) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No habits yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a habit to start tracking your temptations.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                vm.prepareNewHabit()
            }) {
                Label("Add Habit", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func habitFormSheet(_ vm: HabitsViewModel) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Habit name", text: Binding(
                        get: { vm.habitName },
                        set: { vm.habitName = $0 }
                    ))

                    TextField("Description (optional)", text: Binding(
                        get: { vm.habitDescription },
                        set: { vm.habitDescription = $0 }
                    ), axis: .vertical)
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
                                        .stroke(Color.primary, lineWidth: vm.selectedColorHex == color.hex ? 3 : 0)
                                )
                                .onTapGesture {
                                    vm.selectedColorHex = color.hex
                                }
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
                                        .fill(vm.selectedIconName == icon ? Color.blue.opacity(0.2) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(vm.selectedIconName == icon ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    vm.selectedIconName = icon
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Preview
                Section("Preview") {
                    HStack(spacing: 12) {
                        Image(systemName: vm.selectedIconName)
                            .font(.title)
                            .foregroundStyle(Color(hex: vm.selectedColorHex) ?? .blue)

                        VStack(alignment: .leading) {
                            Text(vm.habitName.isEmpty ? "Habit name" : vm.habitName)
                                .font(.headline)
                            if !vm.habitDescription.isEmpty {
                                Text(vm.habitDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(vm.isEditing ? "Edit Habit" : "New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.dismissSheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.saveHabit()
                    }
                    .disabled(!vm.canSave)
                }
            }
        }
    }
}

#Preview {
    HabitsView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self], inMemory: true)
}
