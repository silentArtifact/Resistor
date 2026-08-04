import SwiftUI

/// The Color and Icon sections of a habit form.
///
/// Two forms create or edit a habit — the Habits screen's editor and the Log
/// screen's Add Habit sheet — and they carried identical copies of these grids.
/// One copy, so the icon search only had to be built once and the two can't
/// drift apart.
///
/// Emits two `Section`s, so it goes straight into a `Form`.
struct HabitStylePicker: View {
    @Binding var colorHex: String
    @Binding var iconName: String

    @State private var iconQuery = ""

    private var color: Color { Color(hex: colorHex) ?? .blue }

    /// The selected icon leads the default grid when it isn't one of the
    /// suggested twenty — otherwise editing a habit whose icon came from a
    /// search would open on a grid with nothing selected in it.
    private var icons: [String] {
        let matches = HabitsViewModel.icons(matching: iconQuery)
        guard iconQuery.isEmpty, !iconName.isEmpty, !matches.contains(iconName) else {
            return matches
        }
        return [iconName] + matches
    }

    var body: some View {
        Section("Color") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                ForEach(HabitsViewModel.availableColors, id: \.hex) { swatch in
                    let isSelected = colorHex == swatch.hex
                    Circle()
                        .fill(Color(hex: swatch.hex) ?? .blue)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: isSelected ? 3 : 0)
                        )
                        .onTapGesture { colorHex = swatch.hex }
                        .accessibilityLabel(swatch.name)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 8)
        }

        Section("Icon") {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search symbols", text: $iconQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !iconQuery.isEmpty {
                    Button {
                        iconQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    // Plain, or the whole row becomes the button's tap target.
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }

            if icons.isEmpty {
                Text("No symbols match \"\(iconQuery)\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                    ForEach(icons, id: \.self) { icon in
                        let isSelected = iconName == icon
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(isSelected ? color : Color.primary)
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? color.opacity(0.2) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture { iconName = icon }
                            .accessibilityLabel(Self.iconLabel(icon))
                            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// "cup.and.saucer.fill" reads as "cup and saucer" to VoiceOver.
    static func iconLabel(_ icon: String) -> String {
        icon
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
    }
}
