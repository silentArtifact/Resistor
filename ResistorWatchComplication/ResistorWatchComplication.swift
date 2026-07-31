import SwiftUI
import WidgetKit

/// Watch-face complication that launches the Resistor watch app. Static
/// launcher glyph only — tapping any complication opens its owning app on
/// watchOS, so no widgetURL or deep-link plumbing is needed.
///
// ponytail: no data, no resisted count. Showing one would require moving the
// watch's SwiftData store into an App Group so this extension could read it —
// deferred until there's a reason to.
struct ComplicationEntry: TimelineEntry {
    let date: Date
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(Timeline(entries: [ComplicationEntry(date: .now)], policy: .never))
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Resistor", systemImage: "bolt.shield.fill")
                .containerBackground(.clear, for: .widget)
        case .accessoryCorner:
            glyph
                .padding(2)
                .widgetAccentable()
                .containerBackground(.clear, for: .widget)
        default:
            glyph
                .padding(10)
                .widgetAccentable()
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
    }

    // Resizable, not a fixed .font size: the circular container is ~10pt wider
    // on a 49mm Ultra than on a 40mm, and a fixed glyph clips on the small one.
    private var glyph: some View {
        Image(systemName: "bolt.shield.fill")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Open Resistor")
    }
}

struct ResistorWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ResistorWatchComplication", provider: ComplicationProvider()) { _ in
            ComplicationView()
        }
        .configurationDisplayName("Quick Log")
        .description("Open Resistor to log a resisted temptation.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct ResistorWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        ResistorWatchComplication()
    }
}
