import SwiftUI
import SwiftData
import StoreKit

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    @State private var viewModel: HabitsViewModel?
    @State private var tipJarViewModel = TipJarViewModel()
    @Query(sort: \ContextTag.createdAt) private var contextTags: [ContextTag]
    @State private var showDeleteAllConfirmation = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var newTagName: String = ""
    @Query private var contactPlaces: [ContactPlace]
    @State private var contactMatcher = ContactMatcher()
    /// Owned rather than read from `\.editMode`, because `EditButton` installs
    /// that inside the `NavigationStack` — below this view's own environment —
    /// so the rows could never tell whether the grip hint should stand down.
    @State private var isEditing = false

    /// The user-configured accent color, falling back to the system tint.
    private var accentColor: Color {
        if let hex = userSettings.first?.accentColorHex, let color = Color(hex: hex) {
            return color
        }
        return UserSettings.defaultAccentColor
    }

    /// Reordering only means something with two or more habits to order — and
    /// the first one in that order *is* the habit the Log screen and the watch
    /// open on, so the drag is the whole default-habit mechanism.
    private var canReorder: Bool {
        (viewModel?.activeHabits.count ?? 0) > 1
    }

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
                // Drag-to-reorder needs edit mode; only worth offering once
                // there's more than one active habit to move.
                if canReorder {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        viewModel?.prepareNewHabit()
                    }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Habit")
                    .accessibilityIdentifier("addHabitButton")
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
                    .onMove { source, destination in
                        vm.moveHabits(from: source, to: destination)
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
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
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
            VStack(alignment: .leading, spacing: 4) {
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
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(habit.safeEvents.count)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("logged")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Reorder affordance. Out of edit mode the list gives no hint that
            // the order is the user's to set — and the order decides which habit
            // both the Log screen and the watch open on. In edit mode the system
            // draws its own grip, so this stands down rather than doubling it.
            // Tappable so it isn't a dead affordance: a drag here does nothing
            // until the list is editing.
            if canReorder && !isEditing && !isArchived {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
                    .onTapGesture { isEditing = true }
                    // The row is one combined element; the Edit button is the
                    // VoiceOver path to reordering.
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens habit editor")
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
            if let settings = userSettings.first {
                // Accent color picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent Color")
                        .font(.body)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 40), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(UserSettings.accentPalette, id: \.hex) { color in
                            let isSelected = settings.accentColorHex == color.hex
                            Circle()
                                .fill(Color(hex: color.hex) ?? .blue)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .opacity(isSelected ? 1 : 0)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.9), lineWidth: isSelected ? 2 : 0)
                                        .padding(-3)
                                )
                                .frame(maxWidth: .infinity)
                                .contentShape(Circle())
                                .onTapGesture {
                                    settings.accentColorHex = color.hex
                                    try? modelContext.save()
                                }
                                .accessibilityLabel(color.name)
                                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }

        Section("Context Tags") {
            ForEach(contextTags) { tag in
                Text(tag.name)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    modelContext.delete(contextTags[index])
                }
                try? modelContext.save()
            }

            HStack(spacing: 12) {
                TextField("Add a tag", text: $newTagName)
                    .submitLabel(.done)
                    .onSubmit { addTag() }

                Button(action: addTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }

        contactMatchingSection
    }

    /// Opt-in address-book matching, so naming a place can suggest the person
    /// who lives there.
    ///
    /// An action and a resting state, not a `Toggle`. A toggle would have to
    /// flip itself back off when a run finds nothing to match — every contact
    /// without an address, or access declined — which reads as the switch being
    /// broken. There is no setting here: either matches exist or they don't.
    @ViewBuilder
    private var contactMatchingSection: some View {
        Section {
            if contactPlaces.isEmpty {
                Button("Match My Contacts") {
                    Task { await contactMatcher.rebuild(in: modelContext) }
                }
                .disabled(contactMatcher.isWorking)
            } else {
                LabeledContent(
                    "Matched",
                    value: contactPlaces.count == 1 ? "1 contact" : "\(contactPlaces.count) contacts"
                )
                Button("Remove Contact Matches", role: .destructive) {
                    contactMatcher.clear(in: modelContext)
                }
                .disabled(contactMatcher.isWorking)
            }

            if let statusText = contactMatcher.statusText {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Contacts")
        } footer: {
            Text("Looks up your contacts' addresses once, so naming a place can suggest whoever lives there. Addresses stay on this device.")
        }
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !contextTags.contains(where: { $0.name == trimmed }) else {
            newTagName = ""
            return
        }
        let tag = ContextTag(name: trimmed)
        modelContext.insert(tag)
        try? modelContext.save()
        newTagName = ""
    }

    @ViewBuilder
    private var dataSection: some View {
        Section("Data") {
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
            let jsonData = try DataExporter.exportJSON(habits: habits, events: events)
            let fileURL = try DataExporter.writeToTempFile(jsonData)
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
            try modelContext.delete(model: ContextTag.self)
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

                    // Capped so it can't outrun the Log card, which is the only
                    // place a description is read and can't scroll.
                    TextField("Description (optional)", text: Binding(
                        get: { vm.habitDescription },
                        set: { vm.habitDescription = String($0.prefix(Habit.descriptionCharacterLimit)) }
                    ), axis: .vertical)
                    .lineLimit(2...4)
                }

                HabitStylePicker(
                    colorHex: Binding(
                        get: { vm.selectedColorHex },
                        set: { vm.selectedColorHex = $0 }
                    ),
                    iconName: Binding(
                        get: { vm.selectedIconName },
                        set: { vm.selectedIconName = $0 }
                    )
                )

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
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
}
