import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: OnboardingViewModel?
    @State private var step: OnboardingStep = .intro
    var onComplete: () -> Void

    private enum OnboardingStep {
        case intro
        case firstHabit
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .intro:
                    introStep
                        .transition(reduceMotion
                            ? .opacity
                            : .move(edge: .trailing).combined(with: .opacity))
                case .firstHabit:
                    firstHabitStep
                        .transition(reduceMotion
                            ? .opacity
                            : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
        }
        .onAppear {
            if viewModel == nil {
                viewModel = OnboardingViewModel(modelContext: modelContext)
            }
        }
    }

    // MARK: - Intro Step

    private var introStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Identity block
                VStack(spacing: 16) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("Resistor")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                Spacer().frame(height: 40)

                // Premise block
                VStack(alignment: .leading, spacing: 20) {
                    Text("Log each moment a temptation hits, and whether you resisted or gave in.")
                        .foregroundStyle(Color.primary)

                    Text("Over time, Resistor shows you the patterns: when temptations cluster and how often you resist.")
                        .foregroundStyle(Color.primary)

                    Text("No streaks, no scores, no reminders.")
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                // Forward control
                Button(action: {
                    step = .firstHabit
                }) {
                    Text("Continue")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.accentColor)
                        .cornerRadius(16)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: introMinHeight)
        }
    }

    private var introMinHeight: CGFloat {
        // Allow the centered layout to fill the viewport at default sizes while
        // letting the ScrollView grow past it at the largest Dynamic Type sizes.
        #if canImport(UIKit)
        return UIScreen.main.bounds.height - 100
        #else
        return 600
        #endif
    }

    // MARK: - First Habit Step

    private var firstHabitStep: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)

                Text("Resistor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.top, 40)

            Spacer()

            // Form
            if let vm = viewModel {
                VStack(spacing: 20) {
                    Text("What habit are you working on?")
                        .font(.headline)

                    TextField("e.g., Sugar, Smoking, Social Media", text: Binding(
                        get: { vm.habitName },
                        set: { vm.habitName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                    TextField("Description (optional)", text: Binding(
                        get: { vm.habitDescription },
                        set: { vm.habitDescription = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(HabitsViewModel.availableColors, id: \.hex) { color in
                                    Circle()
                                        .fill(Color(hex: color.hex) ?? .blue)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: vm.selectedColorHex == color.hex ? 3 : 0)
                                        )
                                        .onTapGesture {
                                            vm.selectedColorHex = color.hex
                                        }
                                        .accessibilityLabel(color.name)
                                        .accessibilityAddTraits(vm.selectedColorHex == color.hex ? [.isButton, .isSelected] : .isButton)
                                }
                            }
                            .padding(.horizontal)
                            // Vertical room so the selection ring isn't
                            // clipped by the scroll view's content bounds.
                            .padding(.vertical, 4)
                        }
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(HabitsViewModel.availableIcons, id: \.self) { icon in
                                    Image(systemName: icon)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
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
                                        .accessibilityAddTraits(vm.selectedIconName == icon ? [.isButton, .isSelected] : .isButton)
                                }
                            }
                            .padding(.horizontal)
                            // Vertical room so the selection border isn't
                            // clipped by the scroll view's content bounds.
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Spacer()

            // Actions
            if let vm = viewModel {
                VStack(spacing: 12) {
                    Button(action: {
                        if vm.createFirstHabit() {
                            onComplete()
                        }
                    }) {
                        Text("Create habit and start logging")

                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(vm.canCreateHabit ? Color.blue : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!vm.canCreateHabit)
                    .accessibilityHint(vm.canCreateHabit ? "" : "Enter a habit name first")

                    Button(action: {
                        if vm.skipOnboarding() {
                            onComplete()
                        }
                    }) {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHint("You can add habits later from the Habits tab")
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
}
