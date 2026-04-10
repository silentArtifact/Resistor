import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: OnboardingViewModel?
    var onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)

                    Text("Resistor")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Track your temptations, understand your patterns.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
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
                                            .accessibilityAddTraits(vm.selectedColorHex == color.hex ? .isSelected : [])
                                    }
                                }
                                .padding(.horizontal)
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
                                            .accessibilityAddTraits(vm.selectedIconName == icon ? .isSelected : [])
                                    }
                                }
                                .padding(.horizontal)
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

                        Button(action: {
                            if vm.skipOnboarding() {
                                onComplete()
                            }
                        }) {
                            Text("Skip for now")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = OnboardingViewModel(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
}
