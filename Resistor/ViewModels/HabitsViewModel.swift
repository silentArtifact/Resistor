import Foundation
import SwiftData
import Observation
import UIKit

@Observable
final class HabitsViewModel {
    private var modelContext: ModelContext

    var habits: [Habit] = []
    var showAddHabitSheet: Bool = false
    var habitToEdit: Habit?
    var showDeleteConfirmation: Bool = false
    var habitToDelete: Habit?

    // Form fields for add/edit
    var habitName: String = ""
    var habitDescription: String = ""
    var selectedColorHex: String = HabitsViewModel.availableColors[0].hex
    var selectedIconName: String = "circle.fill"

    var isEditing: Bool {
        habitToEdit != nil
    }

    var canSave: Bool {
        !habitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchHabits()
    }

    func fetchHabits() {
        let descriptor = FetchDescriptor<Habit>(
            sortBy: Habit.displayOrder
        )
        do {
            let all = try modelContext.fetch(descriptor)
            habits = all.sorted { ($0.isArchived ? 1 : 0) < ($1.isArchived ? 1 : 0) }
        } catch {
            print("Failed to fetch habits: \(error)")
            habits = []
        }
    }

    var activeHabits: [Habit] {
        habits.filter { !$0.isArchived }
    }

    var archivedHabits: [Habit] {
        habits.filter { $0.isArchived }
    }

    // MARK: - Add/Edit Habit

    func prepareNewHabit() {
        habitToEdit = nil
        habitName = ""
        habitDescription = ""
        selectedColorHex = HabitsViewModel.availableColors[0].hex
        selectedIconName = "circle.fill"
        showAddHabitSheet = true
    }

    func prepareEditHabit(_ habit: Habit) {
        habitToEdit = habit
        habitName = habit.name
        habitDescription = habit.habitDescription ?? ""
        selectedColorHex = habit.colorHex ?? HabitsViewModel.availableColors[0].hex
        selectedIconName = habit.iconName ?? "circle.fill"
        showAddHabitSheet = true
    }

    func saveHabit() {
        let trimmedName = habitName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let existingHabit = habitToEdit {
            // Update existing
            existingHabit.name = trimmedName
            existingHabit.habitDescription = habitDescription.isEmpty ? nil : habitDescription
            existingHabit.colorHex = selectedColorHex
            existingHabit.iconName = selectedIconName
        } else {
            // Create new
            let newHabit = Habit(
                name: trimmedName,
                habitDescription: habitDescription.isEmpty ? nil : habitDescription,
                colorHex: selectedColorHex,
                iconName: selectedIconName,
                sortOrder: Habit.nextSortOrder(in: modelContext)
            )
            modelContext.insert(newHabit)
        }

        do {
            try modelContext.save()
            fetchHabits()
            dismissSheet()
        } catch {
            print("Failed to save habit: \(error)")
        }
    }

    func dismissSheet() {
        showAddHabitSheet = false
        habitToEdit = nil
        habitName = ""
        habitDescription = ""
        selectedColorHex = HabitsViewModel.availableColors[0].hex
        selectedIconName = "circle.fill"
    }

    // MARK: - Reorder

    /// Applies a drag in the Active Habits list. Rewrites `sortOrder` for the
    /// whole active list rather than nudging the moved habit, so the stored
    /// order stays a dense 0..n-1 and can't drift into ties after repeated
    /// drags. Archived habits are left alone — they're a separate section and
    /// aren't draggable.
    func moveHabits(from source: IndexSet, to destination: Int) {
        var reordered = activeHabits
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in reordered.enumerated() {
            habit.sortOrder = index
        }

        do {
            try modelContext.save()
            fetchHabits()
        } catch {
            print("Failed to reorder habits: \(error)")
        }
    }

    // MARK: - Archive/Delete

    func confirmDelete(_ habit: Habit) {
        habitToDelete = habit
        showDeleteConfirmation = true
    }

    func deleteHabit() {
        guard let habit = habitToDelete else { return }

        // Manual cascade: delete all events for this habit first
        for event in habit.safeEvents {
            modelContext.delete(event)
        }
        modelContext.delete(habit)

        do {
            try modelContext.save()
            fetchHabits()
        } catch {
            print("Failed to delete habit: \(error)")
        }

        habitToDelete = nil
        showDeleteConfirmation = false
    }

    func archiveHabit(_ habit: Habit) {
        habit.isArchived = true

        do {
            try modelContext.save()
            fetchHabits()
        } catch {
            print("Failed to archive habit: \(error)")
        }
    }

    func unarchiveHabit(_ habit: Habit) {
        habit.isArchived = false

        do {
            try modelContext.save()
            fetchHabits()
        } catch {
            print("Failed to unarchive habit: \(error)")
        }
    }

    func cancelDelete() {
        habitToDelete = nil
        showDeleteConfirmation = false
    }
}

// MARK: - Available Colors and Icons

extension HabitsViewModel {
    /// The habit palette, in the same muted register as the accent swatches in
    /// `HabitsView`.
    ///
    /// This used to be the raw iOS system wheel (`#007AFF`, `#34C759`,
    /// `#FF9500`, …), which meant the app shipped two palettes: nine muted hues
    /// the user picked an accent from, and ten fully-saturated ones that then
    /// coloured every habit card, chart bar, history icon and widget — most of
    /// the app's colour. One picker looked designed and the other looked like a
    /// default, because it was one.
    ///
    /// Mid-tone on purpose: a habit colour has to work as chart ink and as a
    /// filled glyph on both a white card and a black one, so nothing here goes
    /// near the light or dark end.
    /// Ordered warm → cool → neutral rather than by when a hue was added, so the
    /// grid reads as a sweep. Sand stays first because index 0 is what a new
    /// habit takes.
    static let availableColors: [(name: String, hex: String)] = [
        ("Sand", "#E8A87C"),
        ("Clay", "#C97B63"),
        ("Brick", "#B4645C"),
        ("Bronze", "#A5734F"),
        ("Ochre", "#C6A15B"),
        ("Moss", "#8A9B5F"),
        ("Sage", "#7F9E76"),
        ("Fern", "#659A65"),
        ("Mint", "#6FAE94"),
        ("Teal", "#5E9E9E"),
        ("Sky", "#6FA3C4"),
        ("Slate Blue", "#6E7FA8"),
        ("Indigo", "#6668A0"),
        ("Periwinkle", "#7D7AA8"),
        ("Violet", "#9070AD"),
        ("Lilac", "#B08FC4"),
        ("Mulberry", "#9C6480"),
        ("Rose", "#C77D8A"),
        ("Storm", "#7A8290"),
        ("Pewter", "#9AA0A8")
    ]

    /// The set shown when the icon search is empty — the common habits, in the
    /// order they were curated. Also the source of the default (`circle.fill`).
    static let availableIcons: [String] = [
        "circle.fill",
        "star.fill",
        "heart.fill",
        "bolt.fill",
        "flame.fill",
        "leaf.fill",
        "drop.fill",
        "moon.fill",
        "sun.max.fill",
        "cloud.fill",
        "cart.fill",
        "creditcard.fill",
        "phone.fill",
        "tv.fill",
        "gamecontroller.fill",
        "cup.and.saucer.fill",
        "fork.knife",
        "wineglass.fill",
        // Not `cigarette.fill` — Apple ships no cigarette symbol under any
        // name, so that entry drew a blank tile from v1 until the availability
        // test caught it. `smoke.fill` carries the smoking keywords instead.
        "smoke.fill",
        "pills.fill"
    ]

    /// Everything else the search can reach. There is no public API to
    /// enumerate SF Symbols, so this is a hand-curated catalogue rather than the
    /// full several-thousand set — which would be unusable in a grid anyway.
    ///
    /// Grouped by what someone might be tracking. `allIcons` drops anything the
    /// running OS doesn't have, so a symbol added in a later SDK degrades to
    /// absent rather than to a blank square.
    static let iconCatalog: [String] = [
        // Shapes and marks
        "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill",
        "seal.fill", "shield.fill", "checkmark.circle.fill", "xmark.circle.fill",
        "exclamationmark.triangle.fill", "questionmark.circle.fill",
        "flag.fill", "flag.checkered", "bookmark.fill", "tag.fill", "pin.fill",
        "sparkles", "sparkle", "infinity", "circle.dashed", "target", "scope",
        "crown.fill", "trophy.fill", "rosette", "burst.fill",

        // Substances
        "mug.fill", "waterbottle.fill", "takeoutbag.and.cup.and.straw.fill",
        "cross.vial.fill", "syringe.fill", "bandage.fill", "lungs.fill",
        "heart.text.square.fill", "cross.case.fill",

        // Food
        "birthday.cake.fill", "carrot.fill", "fish.fill", "popcorn.fill",
        "frying.pan.fill", "refrigerator.fill", "waterbottle",

        // Screens and devices
        "iphone", "ipad", "laptopcomputer", "desktopcomputer", "display",
        "headphones", "airpods", "message.fill", "bubble.left.fill",
        "bubble.left.and.bubble.right.fill", "envelope.fill", "video.fill",
        "camera.fill", "photo.fill", "play.rectangle.fill", "music.note",
        "speaker.wave.2.fill", "wifi", "antenna.radiowaves.left.and.right",
        "globe", "network", "bell.fill", "bell.slash.fill", "keyboard",

        // Money and shopping
        "bag.fill", "dollarsign.circle.fill", "banknote.fill", "giftcard.fill",
        "gift.fill", "percent", "chart.line.uptrend.xyaxis", "wallet.pass.fill",
        "storefront.fill", "chart.bar.fill", "chart.pie.fill",

        // Gambling
        "dice.fill", "suit.spade.fill", "suit.club.fill", "suit.heart.fill",
        "suit.diamond.fill",

        // Body and exercise
        "figure.walk", "figure.run", "figure.stand", "figure.yoga",
        "figure.mind.and.body", "figure.strengthtraining.traditional",
        "figure.pool.swim", "figure.outdoor.cycle", "figure.2",
        "dumbbell.fill", "bicycle", "sportscourt.fill", "tennis.racket",
        "soccerball", "basketball.fill", "football.fill",
        "brain.head.profile", "brain", "eye.fill", "eye.slash.fill",
        "mouth.fill", "ear", "hare.fill", "tortoise.fill",
        "hand.raised.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill",
        "hand.wave.fill",

        // Time and sleep
        "bed.double.fill", "moon.zzz.fill", "zzz", "sunrise.fill",
        "sunset.fill", "alarm.fill", "clock.fill", "timer", "hourglass",
        "calendar", "stopwatch.fill",

        // Places and travel
        "house.fill", "building.2.fill", "building.columns.fill", "car.fill",
        "bus.fill", "tram.fill", "airplane", "fuelpump.fill",
        "mappin.and.ellipse", "location.fill",

        // Work and study
        "briefcase.fill", "book.fill", "books.vertical.fill",
        "graduationcap.fill", "pencil", "highlighter", "doc.fill",
        "folder.fill", "paperclip", "checklist", "list.bullet", "printer.fill",

        // People
        "person.fill", "person.2.fill", "person.3.fill", "heart.slash.fill",

        // Outdoors and weather
        "cloud.rain.fill", "cloud.bolt.fill", "snowflake", "wind", "tree.fill",
        "mountain.2.fill", "water.waves", "pawprint.fill", "ant.fill",
        "bird.fill", "dog.fill", "cat.fill",

        // Tools and pastimes
        "wrench.and.screwdriver.fill", "hammer.fill", "scissors",
        "paintbrush.fill", "paintpalette.fill", "theatermasks.fill",
        "ticket.fill", "gearshape.fill", "trash.fill", "waveform",
        "lock.fill", "key.fill", "arrow.clockwise", "arrow.counterclockwise"
    ]

    /// Search words a symbol's own name doesn't contain. Only the non-obvious
    /// ones are listed — "dice" already finds `dice.fill`, but nothing in
    /// `cup.and.saucer.fill` says coffee.
    static let iconKeywords: [String: String] = [
        "cup.and.saucer.fill": "coffee tea caffeine drink",
        "mug.fill": "coffee tea beer drink",
        "wineglass.fill": "alcohol wine drink booze beer",
        "smoke.fill": "smoking cigarette nicotine tobacco vape",
        "lungs.fill": "smoking cigarette breathing vape",
        "pills.fill": "drugs medication meds",
        "cross.vial.fill": "drugs medical",
        "syringe.fill": "drugs injection",
        "leaf.fill": "cannabis weed plant nature",
        "waterbottle.fill": "water hydration drink",
        "cart.fill": "shopping shop spending",
        "bag.fill": "shopping shop spending",
        "creditcard.fill": "spending money debt",
        "dollarsign.circle.fill": "money spending cash",
        "banknote.fill": "money cash spending",
        "storefront.fill": "shopping shop",
        "dice.fill": "gambling betting casino",
        "suit.spade.fill": "cards gambling poker",
        "suit.club.fill": "cards gambling poker",
        "suit.heart.fill": "cards gambling poker",
        "suit.diamond.fill": "cards gambling poker",
        "gamecontroller.fill": "gaming videogames console",
        "tv.fill": "television streaming binge",
        "display": "computer screen monitor",
        "iphone": "phone screen scrolling",
        "globe": "internet web browsing",
        "network": "internet web",
        "message.fill": "texting chat social",
        "bubble.left.fill": "chat social messaging",
        "photo.fill": "social feed scrolling",
        "eye.fill": "watching porn looking",
        "eye.slash.fill": "avoiding hiding porn",
        "fork.knife": "food eating meals",
        "birthday.cake.fill": "sugar sweets dessert cake",
        "takeoutbag.and.cup.and.straw.fill": "fast food takeaway junk",
        "popcorn.fill": "snacking cinema movies",
        "mouth.fill": "biting chewing nails",
        "bed.double.fill": "sleep bedroom insomnia",
        "zzz": "sleep tired",
        "moon.zzz.fill": "sleep night insomnia",
        "figure.run": "running exercise workout jogging",
        "figure.walk": "walking exercise steps",
        "dumbbell.fill": "gym exercise workout weights",
        "figure.mind.and.body": "meditation mindfulness calm",
        "brain.head.profile": "mind thinking anxiety rumination",
        "brain": "mind thinking anxiety",
        "car.fill": "driving commute",
        "house.fill": "home",
        "briefcase.fill": "work job office",
        "book.fill": "reading study",
        "graduationcap.fill": "study school learning",
        "clock.fill": "time procrastination",
        "hourglass": "time waiting procrastination",
        "person.2.fill": "friends social people",
        "heart.slash.fill": "breakup relationship",
        "hand.raised.fill": "stop resist",
        "flame.fill": "burn urge craving",
        "bolt.fill": "energy urge impulse",
        "music.note": "music listening",
        "headphones": "music audio podcast",
        "paintbrush.fill": "art creative hobby",
        "scissors": "cutting hair",
        "lock.fill": "blocking restricting",
        "trash.fill": "waste"
    ]

    /// Suggested set plus catalogue, minus anything this OS can't draw.
    static let allIcons: [String] = (availableIcons + iconCatalog)
        .filter { UIImage(systemName: $0) != nil }

    /// Icons for a search box: the suggested set when the query is empty, and
    /// otherwise every catalogue symbol matching all of the query's words —
    /// against the symbol name (dots read as spaces) and its keywords.
    static func icons(matching query: String) -> [String] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return availableIcons }
        return allIcons.filter { icon in
            let haystack = icon.replacingOccurrences(of: ".", with: " ")
                + " " + (iconKeywords[icon] ?? "")
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
