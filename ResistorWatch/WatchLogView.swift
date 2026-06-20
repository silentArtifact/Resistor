import SwiftUI
import WatchKit

/// The watch Quick-Log screen. ONE screen, no NavigationStack/tabs/Crown.
/// Tap-only: one tap → one resisted `TemptationEvent`. The phone's 3s hold ramp
/// is deliberately dropped on the watch.
struct WatchLogView: View {
    @State private var vm: WatchLogStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Debounce window: the button is disabled briefly after a tap so a
    /// double-contact yields exactly one event.
    private static let debounce: TimeInterval = 0.8
    /// How long the "Logged" acknowledgement dwells before auto-dismissing.
    private static let ackDwell: TimeInterval = 1.2

    @State private var isLogging = false
    @State private var showAck = false

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .onAppear {
            if vm == nil {
                vm = WatchLogStore()
            } else {
                vm?.refresh()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.state {
            case let .loggable(_, name, colorHex, iconName, count):
                loggable(name: name, colorHex: colorHex, iconName: iconName, count: count)
            case .noHabit:
                nonLoggable(
                    symbol: "square.dashed",
                    title: "No habit to log",
                    subtitle: "Add a habit on your phone"
                )
            case .habitUnavailable:
                nonLoggable(
                    symbol: "exclamationmark.triangle",
                    title: "Habit unavailable",
                    subtitle: "Set a default habit on your phone"
                )
            }
        } else {
            // Pre-init frame; render nothing rather than a flash of wrong state.
            Color.clear.frame(height: 1)
        }
    }

    // MARK: - (a)/(b)/(c)/(f) Loggable

    @ViewBuilder
    private func loggable(name: String, colorHex: String?, iconName: String?, count: Int?) -> some View {
        let habitColor = Color(hex: colorHex ?? "#007AFF") ?? .blue
        let symbol = iconName ?? "circle.fill"

        VStack(spacing: 8) {
            Text(name)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            ZStack {
                Button(action: handleTap) {
                    Circle()
                        .fill(isLogging ? habitColor.opacity(0.5) : habitColor)
                        .overlay(
                            Image(systemName: symbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                        .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .disabled(isLogging)

                acknowledgement
            }
            .frame(maxWidth: .infinity)
            .frame(width: buttonContainerWidth)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(buttonAccessibilityLabel(name: name, count: count))
            .accessibilityHint("Logs a resisted temptation.")
            .accessibilityAction { handleTap() }

            countLine(count: count)
        }
        .padding(.horizontal, 4)
    }

    /// Caps the button width to ~60–66% of the screen so the circle stays the
    /// designed proportion regardless of watch size.
    private var buttonContainerWidth: CGFloat {
        WKInterfaceDevice.current().screenBounds.width * 0.63
    }

    @ViewBuilder
    private var acknowledgement: some View {
        if showAck {
            VStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Logged")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .padding(8)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .transition(reduceMotion ? .identity : .scale(scale: 0.9).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func countLine(count: Int?) -> some View {
        Group {
            if let count {
                ViewThatFits {
                    Text("Today: \(count) logged")
                    Text("\(count) today")
                }
            } else {
                Text("Count unavailable")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityHidden(true) // folded into the button label
    }

    private func buttonAccessibilityLabel(name: String, count: Int?) -> String {
        if let count {
            return "\(name), \(count) logged today"
        }
        return "\(name), count unavailable"
    }

    // MARK: - (d)/(e) Non-loggable

    @ViewBuilder
    private func nonLoggable(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle).")
    }

    // MARK: - Interaction

    private func handleTap() {
        guard let vm, !isLogging else { return }

        // (b) in-flight: disable + dim immediately. Snap when Reduce Motion.
        if reduceMotion {
            isLogging = true
        } else {
            withAnimation(.easeInOut(duration: 0.12)) { isLogging = true }
        }

        let success = vm.logResisted()

        guard success else {
            // Re-enable; no error/shake per spec.
            reEnableAfterDebounce()
            return
        }

        // Haptic on successful log only.
        WKInterfaceDevice.current().play(.success)

        // (c) success ack: a display layer over a still-live button.
        if reduceMotion {
            showAck = true
        } else {
            withAnimation(.easeOut(duration: 0.15)) { showAck = true }
        }

        // Re-enable the button after the debounce so a real second urge can
        // re-tap and restart the ack while it is still showing.
        reEnableAfterDebounce()

        // Auto-dismiss the ack after its dwell.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ackDwell) {
            if reduceMotion {
                showAck = false
            } else {
                withAnimation(.easeIn(duration: 0.2)) { showAck = false }
            }
        }
    }

    private func reEnableAfterDebounce() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce) {
            if reduceMotion {
                isLogging = false
            } else {
                withAnimation(.easeInOut(duration: 0.12)) { isLogging = false }
            }
        }
    }
}
