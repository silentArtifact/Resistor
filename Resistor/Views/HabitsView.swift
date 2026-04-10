import SwiftUI
import SwiftData
import StoreKit

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    @State private var viewModel: HabitsViewModel?
    @State private var tipJarViewModel = TipJarViewModel()
    @State private var showDeleteAllConfirmation = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?

    private static let accentColors: [(name: String, hex: String)] = [
        ("Slate Blue", "#6B7FA3"),
        ("Storm Gray", "#7A7F8A"),
        ("Sage", "#7A8F7A"),
        ("Dusty Rose", "#A37A7A"),
        ("Copper", "#A3897A"),
        ("Lavender", "#8A7FA3"),
        ("Teal", "#6B9E9E"),
        ("Charcoal", "#5A5A5F"),
        ("Dusk", "#8A7A99"),
    ]

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
            if viewModel == nil {
                viewModel = HabitsViewModel(modelContext: modelContext)
            } else {
                viewModel?.fetchHabits()
            }
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
        .alert("Delete all data?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This removes all habits, events, and settings. This cannot be undone.")
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(url: url)
            }
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

            // Data section
            dataSection

            // Tip jar
            tipJarSection
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
                HStack(spacing: 6) {
                    Text(habit.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if userSettings.first?.defaultHabitId == habit.id {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }

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
                Text("\(habit.safeEvents.count)")
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
        .contextMenu {
            if !isArchived {
                Button {
                    setDefaultHabit(habit)
                } label: {
                    Label(
                        userSettings.first?.defaultHabitId == habit.id ? "Remove as Default" : "Set as Default",
                        systemImage: "star"
                    )
                }
            }
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

    private func setDefaultHabit(_ habit: Habit) {
        guard let settings = userSettings.first else { return }
        if settings.defaultHabitId == habit.id {
            settings.defaultHabitId = nil
        } else {
            settings.defaultHabitId = habit.id
        }
        try? modelContext.save()
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

                // Accent color picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent Color")
                        .font(.body)

                    HStack(spacing: 8) {
                        ForEach(Self.accentColors, id: \.hex) { color in
                            Circle()
                                .fill(Color(hex: color.hex) ?? .blue)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .opacity(settings.accentColorHex == color.hex ? 1 : 0)
                                )
                                .onTapGesture {
                                    settings.accentColorHex = color.hex
                                    try? modelContext.save()
                                }
                                .accessibilityLabel(color.name)
                                .accessibilityAddTraits(settings.accentColorHex == color.hex ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Button("Export Data") {
                exportData()
            }

            Button("Delete All Data", role: .destructive) {
                showDeleteAllConfirmation = true
            }
        }
    }

    @ViewBuilder
    private var tipJarSection: some View {
        if tipJarViewModel.purchaseState == .thanked {
            Section {
                Text("Thank you.")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } header: {
                Text("Tip Jar")
            }
        } else if let product = tipJarViewModel.product {
            Section {
                Button {
                    Task { await tipJarViewModel.purchase() }
                } label: {
                    HStack {
                        Text("Leave a Tip")
                            .font(.body)
                        Spacer()
                        if tipJarViewModel.purchaseState == .purchasing {
                            ProgressView()
                        } else {
                            Text(product.displayPrice)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(tipJarViewModel.purchaseState == .purchasing)
            } header: {
                Text("Tip Jar")
            } footer: {
                Text("Tips help support development. Completely optional.")
            }
        }
    }

    private func exportData() {
        do {
            let habits = try modelContext.fetch(FetchDescriptor<Habit>())
            let events = try modelContext.fetch(FetchDescriptor<TemptationEvent>())

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let habitsJSON: [[String: Any]] = habits.map { habit in
                var dict: [String: Any] = [
                    "id": habit.id.uuidString,
                    "name": habit.name,
                    "is_archived": habit.isArchived,
                    "created_at": formatter.string(from: habit.createdAt)
                ]
                dict["description"] = habit.habitDescription ?? NSNull()
                dict["color_hex"] = habit.colorHex ?? NSNull()
                dict["icon_name"] = habit.iconName ?? NSNull()
                return dict
            }

            let eventsJSON: [[String: Any]] = events.map { event in
                var dict: [String: Any] = [
                    "id": event.id.uuidString,
                    "occurred_at": formatter.string(from: event.occurredAt),
                    "outcome": event.outcome,
                    "context_tags": event.contextTags
                ]
                dict["habit_id"] = event.habit?.id.uuidString ?? NSNull()
                dict["intensity"] = event.intensity ?? NSNull()
                dict["note"] = event.note ?? NSNull()
                return dict
            }

            let exportData: [String: Any] = [
                "exported_at": formatter.string(from: Date()),
                "habits": habitsJSON,
                "events": eventsJSON
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])

            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("resistor-export.json")
            try jsonData.write(to: fileURL)

            exportURL = fileURL
            showExportSheet = true
        } catch {
            print("Failed to export data: \(error)")
        }
    }

    private func deleteAllData() {
        do {
            try modelContext.delete(model: TemptationEvent.self)
            try modelContext.delete(model: Habit.self)
            try modelContext.delete(model: UserSettings.self)

            let newSettings = UserSettings()
            modelContext.insert(newSettings)
            try modelContext.save()

            viewModel?.fetchHabits()
        } catch {
            print("Failed to delete all data: \(error)")
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
                                .accessibilityLabel(color.name)
                                .accessibilityAddTraits(vm.selectedColorHex == color.hex ? .isSelected : [])
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
                                .accessibilityLabel(icon.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                                .accessibilityAddTraits(vm.selectedIconName == icon ? .isSelected : [])
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

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HabitsView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self], inMemory: true)
}
