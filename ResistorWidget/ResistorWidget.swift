import WidgetKit
import SwiftUI

/// The configurable Quick-Log widget. Each placed instance binds to one habit
/// (chosen via `SelectHabitIntent` in Edit Widget) and logs a resisted
/// temptation on tap. Supports systemSmall and systemMedium only.
struct ResistorWidget: Widget {
    static let kind = "ResistorQuickLogWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectHabitIntent.self,
            provider: QuickLogProvider()
        ) { entry in
            QuickLogWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Log")
        .description("Tap to log a resisted temptation for one habit.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
