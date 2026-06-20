import SwiftUI
import WidgetKit

/// Root view that routes the resolved `QuickLogState` to the correct layout for
/// the active widget family (small or medium). All states are dark-mode-first
/// and use only adaptive system colors plus the habit color.
struct QuickLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickLogEntry

    var body: some View {
        switch entry.state {
        case let .configured(habitID, name, colorHex, iconName, count):
            ConfiguredView(
                family: family,
                habitID: habitID,
                name: name,
                color: habitColor(colorHex),
                iconName: iconName ?? "circle.fill",
                count: count
            )
        case .unconfigured:
            UnconfiguredView(
                family: family,
                glyph: "square.dashed",
                primary: family == .systemSmall ? "No habit selected" : "No habit selected",
                secondary: "Choose a habit in Edit Widget",
                voiceOverLabel: "No habit selected. Choose a habit in Edit Widget.",
                voiceOverHint: "Long press to edit this widget."
            )
        case .needsReconfiguration:
            UnconfiguredView(
                family: family,
                glyph: "exclamationmark.triangle",
                primary: "Habit unavailable",
                secondary: "Edit widget to choose another",
                voiceOverLabel: "Habit unavailable. Edit widget to choose another.",
                voiceOverHint: "Long press to edit this widget."
            )
        case let .storeUnavailable(habitID, name, colorHex, iconName):
            StoreUnavailableView(
                family: family,
                habitID: habitID,
                name: name,
                color: habitColor(colorHex),
                iconName: iconName ?? "circle.fill"
            )
        }
    }

    private func habitColor(_ hex: String?) -> Color {
        Color(hex: hex ?? "#007AFF") ?? .blue
    }
}

// MARK: - (a) Configured / at-rest

private struct ConfiguredView: View {
    let family: WidgetFamily
    let habitID: UUID
    let name: String
    let color: Color
    let iconName: String
    let count: Int

    var body: some View {
        Button(intent: LogResistedIntent(habitID: habitID)) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) logged today")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Logs a resisted temptation.")
        .containerBackground(for: .widget) {
            Color(.systemBackground).overlay(color.opacity(0.12))
        }
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemSmall {
            small
        } else {
            medium
        }
    }

    private var iconToken: some View {
        IconToken(systemName: iconName, glyphColor: color, size: family == .systemSmall ? 44 : 48, glyphPoint: family == .systemSmall ? 28 : 30, fillColor: color.opacity(0.18))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            iconToken
            Text(name)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
                .padding(.top, 8)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text("today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            iconToken
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
                Text("Today: \(count) logged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - (b) Unconfigured & (c) Needs-reconfiguration (no Button)

private struct UnconfiguredView: View {
    let family: WidgetFamily
    let glyph: String
    let primary: String
    let secondary: String
    let voiceOverLabel: String
    let voiceOverHint: String

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(voiceOverLabel)
            .accessibilityHint(voiceOverHint)
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
    }

    private var mutedToken: some View {
        IconToken(
            systemName: glyph,
            glyphColor: .secondary,
            size: family == .systemSmall ? 44 : 48,
            glyphPoint: family == .systemSmall ? 28 : 30,
            fillColor: Color(.secondarySystemFill)
        )
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 8) {
                mutedToken
                Spacer(minLength: 4)
                Text(primary)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
            }
        } else {
            HStack(spacing: 16) {
                mutedToken
                VStack(alignment: .leading, spacing: 4) {
                    Text(primary)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.primary)
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - (d) Store-unavailable (keeps Button)

private struct StoreUnavailableView: View {
    let family: WidgetFamily
    let habitID: UUID
    let name: String
    let color: Color
    let iconName: String

    var body: some View {
        Button(intent: LogResistedIntent(habitID: habitID)) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), count unavailable")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Logs a resisted temptation. Count updates later.")
        .containerBackground(for: .widget) {
            Color(.systemBackground).overlay(color.opacity(0.12))
        }
    }

    private var iconToken: some View {
        IconToken(
            systemName: iconName,
            glyphColor: color,
            size: family == .systemSmall ? 44 : 48,
            glyphPoint: family == .systemSmall ? 28 : 30,
            fillColor: color.opacity(0.18)
        )
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
                iconToken
                Text(name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
                    .padding(.top, 8)
                Spacer(minLength: 4)
                Text("Count unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 16) {
                iconToken
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.primary)
                    Text("Count unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tap to log; count updates later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared icon token

private struct IconToken: View {
    let systemName: String
    let glyphColor: Color
    let size: CGFloat
    let glyphPoint: CGFloat
    let fillColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fillColor)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: glyphPoint))
                    .foregroundStyle(glyphColor)
            )
    }
}
