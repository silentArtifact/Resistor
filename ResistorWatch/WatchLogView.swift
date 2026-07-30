import SwiftUI
import WatchKit

/// The watch Quick-Log screen. ONE screen, no NavigationStack/tabs/Crown.
///
/// Releasing logs — at any point, whether that was a tap or a three-second hold.
/// The hold is not a commit gesture with a threshold; the ramp (filling progress
/// ring, breathing glow, radiating ring, escalating haptics) is the phone's
/// moment of deliberation, and holding past the end keeps buzzing until release.
/// Shaking the wrist within `undoWindow` of a log deletes it again.
struct WatchLogView: View {
    @State private var vm: WatchLogStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Debounce window: the button is disabled briefly after a log so a
    /// double-contact yields exactly one event.
    private static let debounce: TimeInterval = 0.8
    /// How long an acknowledgement dwells before auto-dismissing.
    private static let ackDwell: TimeInterval = 1.2
    /// How long after a log a shake will still undo it. Matches the phone
    /// confirmation banner's 5s undo window, and deliberately outlasts the
    /// acknowledgement — the ack is a report that the log happened, not the undo
    /// affordance, so tying the two together would mean either a needlessly long
    /// ack or a needlessly short window.
    private static let undoWindow: TimeInterval = 5.0
    /// Hold ramp length. Matches the phone's 3s so the same gesture carries the
    /// same deliberate pause on both devices. Holding longer is allowed and keeps
    /// the haptic going; the ramp just sits at full.
    private static let holdDuration: TimeInterval = 3.0
    /// A `minimumDuration` no press will ever reach, so the long-press gesture
    /// never succeeds and only reports pressing/not-pressing. A day, not
    /// `.infinity` or `.greatestFiniteMagnitude` — those land in SwiftUI's
    /// deadline arithmetic, and a non-finite deadline is a worse bet than a
    /// number that is merely absurd.
    private static let neverCompletes: TimeInterval = 86_400

    /// watchOS has no Core Haptics — `CHHapticEngine` is absent from the watchOS
    /// SDK entirely, so the phone's continuous pattern with ramped intensity and
    /// sharpness cannot be ported. `WKInterfaceDevice.play` fires discrete taps
    /// only. The nearest equivalent to "ongoing vibration that escalates" is a
    /// repeated `.click` whose gap tightens from max to min across the ramp,
    /// which reads on the wrist as an accelerating buzz.
    private static let hapticGapMax: TimeInterval = 0.10
    /// Empirical, and the only way to set it — measured on an Apple Watch Series
    /// 8: 0.03s and 0.05s both dropped ticks, 0.07s did not but reads as countable
    /// taps. 0.07s is therefore the floor: the tightest gap the engine delivers
    /// cleanly, and no setting is both seamless and gap-free. Erring toward
    /// gap-free, because a dropped tick is a stutter — a worse artefact than a
    /// buzz you could count if you tried. Don't tighten it without re-measuring
    /// on a device; the simulator plays no haptics at all.
    private static let hapticGapMin: TimeInterval = 0.07

    /// Which acknowledgement is showing, if any. An enum rather than two bools so
    /// "logged" and "undone" can't both be on screen.
    private enum Acknowledgement {
        case logged
        case undone
    }

    @State private var isLogging = false
    @State private var ack: Acknowledgement?
    /// Bumped on every acknowledgement so a previous dwell timer can't dismiss a
    /// newer one early (log, undo, log again inside the dwell).
    @State private var ackGeneration = 0
    /// Same guard for the undo window, which outlives the acknowledgement: a
    /// second log inside the window must not have its listener torn down by the
    /// first log's expiry timer.
    @State private var undoGeneration = 0
    /// Whether an undo is currently on offer. Tracked explicitly rather than read
    /// off `shakeDetector.isRunning`, which isn't observable — and gated on the
    /// window rather than the acknowledgement, so the VoiceOver action is
    /// available for exactly as long as a shake is.
    @State private var canUndo = false
    @State private var shakeDetector = ShakeDetector()

    // MARK: Hold state
    @State private var isHolding = false
    /// 0→1 across `holdDuration`. Driven by ONE linear animation rather than the
    /// phone's 30fps `Timer`: the watch interpolates it on the animation thread,
    /// so the ring/scale/glow cost no per-frame view rebuilds.
    @State private var holdProgress: CGFloat = 0
    @State private var holdStartTime: Date?
    @State private var hapticTimer: Timer?
    @State private var glowPulsing = false

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
        .onChange(of: scenePhase) { _, phase in
            // Re-read the count on resume. `onAppear` does not fire again when the
            // app returns from background, so without this a CloudKit import that
            // landed while suspended stays invisible — the count would show the
            // value from whenever the view was first built.
            //
            // ponytail: resume only. An import that lands while the app is already
            // frontmost still won't show until the next resume; catching that needs
            // NSPersistentStoreRemoteChange observation. Add it only if a stale
            // count is actually noticed in use — a watch glance is a resume.
            guard phase == .active else {
                // Dropping the wrist mid-hold would otherwise strand the haptic
                // timer, buzzing with the app no longer frontmost — and leave the
                // accelerometer running against the battery for an undo the user
                // can no longer see offered.
                endHold()
                disarmUndo()
                return
            }
            vm?.refresh()
        }
        .onDisappear {
            endHold()
            disarmUndo()
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
        // Surrounding chrome recedes during the hold so the button is the only
        // thing left, matching the phone's dimming of its carousel and labels.
        let dim = reduceMotion ? 0.0 : Double(holdProgress) * 0.5

        VStack(spacing: 8) {
            Text(name)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .opacity(1 - dim)

            ZStack {
                logButton(habitColor: habitColor, symbol: symbol)
                acknowledgement
            }
            .frame(maxWidth: .infinity)
            .frame(width: buttonContainerWidth)
            // ONE gesture drives tap and hold alike: press starts the ramp,
            // release logs. There is no completion threshold, so `perform` has no
            // job — and `minimumDuration` is set far beyond any real press
            // precisely so it never fires. A long press that *succeeds* ends the
            // gesture, which would report the press as over while the finger is
            // still down: the buzz would cut out at 3s instead of continuing
            // until release, which is the opposite of what's wanted.
            .onLongPressGesture(
                minimumDuration: Self.neverCompletes,
                maximumDistance: 20,
                perform: {},
                onPressingChanged: { pressing in
                    if pressing { startHold() } else { releaseHold() }
                }
            )
            // Belt and braces for the primary path: if a very quick tap doesn't
            // register as a press at all, this still logs it. A tap that fires
            // both paths is harmless — the `isLogging` debounce swallows the
            // second.
            .onTapGesture(perform: performLog)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(buttonAccessibilityLabel(name: name, count: count))
            .accessibilityHint("Logs a resisted temptation.")
            .accessibilityAction { performLog() }
            // Shake is a motion-only affordance, which is no use to someone who
            // can't shake their wrist reliably — or who would trigger it by
            // accident. Offer the same undo as a VoiceOver action while the window
            // is open. It adds no visible control, so it can't collide with the
            // press gesture the way an on-screen button would.
            .accessibilityActions {
                if canUndo {
                    Button("Undo last log") { performUndo() }
                }
            }

            countLine(count: count)
                .opacity(1 - dim)
        }
        .padding(.horizontal, 4)
    }

    /// The habit-color disc, with the hold effect layered over and behind it.
    /// Mirrors the phone card's layer order — fill, progress ring, blurred glow
    /// border, radiating ring, layered shadows, scale, icon glow — sized for a
    /// circle on a wrist rather than a rounded rect on a phone.
    ///
    /// Split across typed `let` bindings for the same reason as the phone's
    /// `habitCard`: as one fluent chain the decoration overwhelms the Swift
    /// type-checker's solver. The resulting view tree is identical.
    private func logButton(habitColor: Color, symbol: String) -> some View {
        let scale = reduceMotion ? 1.0 : 1.0 + (holdProgress * 0.08)
        // Breathing multiplier — the pulse animation drives this between 0.5 and 1.
        let pulse: CGFloat = glowPulsing ? 1.0 : 0.5

        // The icon is white on a habit-color disc (the phone's is habit-color on
        // a neutral card), so its glow is white — it reads as the glyph
        // brightening rather than smearing into the fill.
        let core = Circle()
            .fill(isLogging ? habitColor.opacity(0.5) : habitColor)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(
                        color: .white.opacity(isHolding ? Double(holdProgress) * 0.9 : 0),
                        radius: isHolding ? 3 + holdProgress * 7 : 0
                    )
            )
            .aspectRatio(1, contentMode: .fit)

        // Rings sit ON the disc, so they are white — a habit-color ring on a
        // habit-color fill would be invisible.
        let ringed = core
            .overlay(
                // Progress trim ring — shows exactly how far along the hold is.
                // Deliberately NOT gated on Reduce Motion: it is the gesture's
                // only progress feedback, not decoration.
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90)) // start at 12 o'clock
                    .opacity(isHolding ? 1 : 0)
            )
            .overlay(
                // Pulsing glow border — breathes via the repeating animation.
                Circle()
                    .stroke(
                        .white.opacity(holdProgress * pulse * 0.8),
                        lineWidth: 2 + holdProgress * 3
                    )
                    .blur(radius: 3)
                    .opacity(isHolding ? 1 : 0)
            )

        // Behind the disc, on the dark canvas, habit color reads — so the
        // radiating ring and halo shadows use it. Radii are roughly half the
        // phone's; the watch canvas is a fraction of the width.
        return ringed
            .background(
                Circle()
                    .stroke(habitColor.opacity(0.4), lineWidth: 2)
                    .scaleEffect(isHolding && !reduceMotion ? 1.0 + holdProgress * 0.15 : 1.0)
                    .opacity(isHolding ? Double(1.0 - holdProgress) * 0.6 : 0)
            )
            .shadow(
                color: habitColor.opacity(isHolding ? Double(holdProgress * pulse) * 0.5 : 0),
                radius: isHolding ? 6 + holdProgress * 10 : 0
            )
            .shadow(
                color: habitColor.opacity(isHolding ? Double(holdProgress * pulse) * 0.25 : 0),
                radius: isHolding ? 14 + holdProgress * 16 : 0
            )
            .scaleEffect(scale)
    }

    /// Caps the button width to ~60–66% of the screen so the circle stays the
    /// designed proportion regardless of watch size.
    private var buttonContainerWidth: CGFloat {
        WKInterfaceDevice.current().screenBounds.width * 0.63
    }

    @ViewBuilder
    private var acknowledgement: some View {
        if let ack {
            VStack(spacing: 2) {
                Image(systemName: ack == .logged ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(ack == .logged ? .green : .secondary)
                Text(ack == .logged ? "Logged" : "Undone")
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

    // MARK: - Hold

    private func startHold() {
        guard let vm, !isLogging, !isHolding else { return }
        guard case .loggable = vm.state else { return }

        isHolding = true
        holdStartTime = Date()

        holdProgress = 0
        withAnimation(.linear(duration: Self.holdDuration)) { holdProgress = 1 }
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                glowPulsing = true
            }
        }
        scheduleHapticTick()
    }

    /// Finger lifted — the log happens here, at whatever progress the ramp
    /// reached. A flick and a full three-second hold both log; the ramp only ever
    /// changed how it felt getting there.
    private func releaseHold() {
        let wasHolding = isHolding
        endHold()
        guard wasHolding else { return }
        performLog()
    }

    /// Tears down the hold without logging. Idempotent: fires on release, on
    /// backgrounding, and on disappear.
    private func endHold() {
        hapticTimer?.invalidate()
        hapticTimer = nil
        holdStartTime = nil
        guard isHolding else { return }
        isHolding = false
        withAnimation(.easeOut(duration: 0.25)) { glowPulsing = false }
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) { holdProgress = 0 }
    }

    /// Self-rescheduling one-shot rather than a fixed-interval repeating timer:
    /// `Timer`'s interval can't change mid-flight, and this way each tick lands
    /// at its exact ramped gap and the timer wakes only when a tap is due.
    private func scheduleHapticTick() {
        guard let start = holdStartTime else { return }
        // Capped at 1, so holding past `holdDuration` keeps ticking at the
        // tightest gap rather than stopping — the buzz runs until release.
        let progress = min(Date().timeIntervalSince(start) / Self.holdDuration, 1.0)
        let gap = Self.hapticGapMax - (Self.hapticGapMax - Self.hapticGapMin) * progress

        hapticTimer = Timer.scheduledTimer(withTimeInterval: gap, repeats: false) { [self] _ in
            guard isHolding else { return }
            WKInterfaceDevice.current().play(.click)
            scheduleHapticTick()
        }
    }

    // MARK: - Log

    private func performLog() {
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

        // Haptic on successful log only. After a hold, this lands as the payoff
        // punch at the end of the escalating clicks.
        WKInterfaceDevice.current().play(.success)

        // (c) success ack: a display layer over a still-live button.
        show(.logged, for: Self.ackDwell)
        armUndo()

        // Re-enable the button after the debounce so a real second urge can
        // re-tap and restart the ack while it is still showing.
        reEnableAfterDebounce()
    }

    /// Listens for a shake for `undoWindow`, then stops. Re-arming over a
    /// still-live window is fine: the store's `lastLoggedEvent` now points at the
    /// newer event, which is the one a shake should remove.
    private func armUndo() {
        undoGeneration += 1
        let generation = undoGeneration
        canUndo = true
        shakeDetector.start(onShake: performUndo)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoWindow) {
            // A newer log has re-armed with a fresh window — leave it running.
            guard generation == undoGeneration else { return }
            disarmUndo()
        }
    }

    private func disarmUndo() {
        canUndo = false
        shakeDetector.stop()
    }

    /// Deletes the event the last log created. Wired to a wrist shake, so it must
    /// be silent about failure — there is no way to have "meant" a shake that
    /// arrives after the window, and nagging about it would be noise.
    private func performUndo() {
        disarmUndo()
        guard let vm, vm.undoLast() else { return }

        // Distinct from `.success` so the wrist can tell a log from an un-log
        // without looking.
        WKInterfaceDevice.current().play(.retry)
        show(.undone, for: Self.ackDwell)
    }

    /// Shows an acknowledgement and schedules its dismissal, invalidating any
    /// dwell timer still pending from a previous one.
    private func show(_ next: Acknowledgement, for dwell: TimeInterval) {
        ackGeneration += 1
        let generation = ackGeneration

        if reduceMotion {
            ack = next
        } else {
            withAnimation(.easeOut(duration: 0.15)) { ack = next }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + dwell) {
            // A newer acknowledgement (or an undo) has taken over — leave it be.
            guard generation == ackGeneration else { return }
            // Note: does NOT stop the shake listener. The undo window outlives
            // this dwell and `armUndo` owns its teardown.
            if reduceMotion {
                ack = nil
            } else {
                withAnimation(.easeIn(duration: 0.2)) { ack = nil }
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
