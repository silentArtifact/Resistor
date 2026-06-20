import AppIntents
import WidgetKit

/// Configuration intent for the Quick-Log widget. Each placed widget is bound to
/// exactly ONE habit, chosen here in the system "Edit Widget" sheet. The picker
/// is backed by `HabitAppEntity` over the user's non-archived habits.
struct SelectHabitIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Habit"
    static var description = IntentDescription("Choose which habit this widget logs.")

    @Parameter(title: "Habit")
    var habit: HabitAppEntity?

    init() {}

    init(habit: HabitAppEntity?) {
        self.habit = habit
    }
}
