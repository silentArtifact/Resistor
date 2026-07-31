import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @Query private var userSettings: [UserSettings]

    private var accentColor: Color {
        if let hex = userSettings.first?.accentColorHex,
           let color = Color(hex: hex) {
            return color
        }
        return UserSettings.defaultAccentColor
    }

    @State private var viewModel: LogViewModel?
    @State private var locationManager = LocationManager()
    @Query(sort: \ContextTag.createdAt) private var contextTags: [ContextTag]
    @State private var selectedTagNames: Set<String> = []
    @State private var showAddHabitSheet = false
    @State private var cardDragOffset: CGFloat = 0
    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    @State private var holdStartTime: Date?
    // Track whether the drag gesture triggered a hold, so onTapGesture can skip
    @State private var didHold = false
    // Pulsing glow toggle (driven by repeating animation)
    @State private var glowPulsing = false
    // Direction of the most recent habit switch, picking the card slide edges
    @State private var slideForward = true

    private func logTemptationAction(_ vm: LogViewModel) {
        // Intersect with current tags to drop any that were deleted while selected
        let validNames = Set(contextTags.map(\.name))
        let tagsToLog = selectedTagNames.intersection(validNames)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Only confirm if the event actually persisted; otherwise the banner
        // would claim a log that didn't happen and its Undo could delete a
        // previously logged event.
        guard vm.logTemptation(contextTags: Array(tagsToLog)) else { return }
        vm.triggerConfirmation()
        // The confirmation banner is a transient visual; VoiceOver won't read it
        // on its own, so post an explicit announcement of the result.
        UIAccessibility.post(notification: .announcement, argument: "Temptation logged")
    }

    /// Every habit switch — swipe, chevron, or VoiceOver action — routes here so
    /// the card always slides in the direction the change implies, and so any
    /// leftover drag offset settles as part of the same animation.
    private func switchHabit(_ vm: LogViewModel, forward: Bool) {
        slideForward = forward
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            if forward { vm.selectNextHabit() } else { vm.selectPreviousHabit() }
            cardDragOffset = 0
        }
    }

    /// The outgoing card leaves the way the finger went; the incoming one enters
    /// from the far edge. Opacity rides along because `.move` only travels the
    /// card's own width — it stops at the 24pt page margin, so the trailing sliver
    /// would otherwise blink out at the screen edge.
    private var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    /// A hold and a carousel swipe both start as a finger landing on the card, so
    /// committing to hold state at touch-down made *every* swipe flash the hold
    /// visuals (the resting border cuts to 0, rings and vignette appear) and fire
    /// haptics, only to cancel them a frame later. Arm first; `startHold` runs
    /// only if the finger is still roughly where it landed after the window.
    /// `holdStartTime` marks "armed or holding" so the swipe branch can cancel it.
    private func armHold(_ vm: LogViewModel) {
        holdStartTime = Date()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [self] _ in
            startHold(vm)
        }
    }

    private func startHold(_ vm: LogViewModel) {
        isHolding = true
        didHold = true
        holdProgress = 0
        holdStartTime = Date()
        vm.startContinuousHaptic()

        // Start pulsing glow animation
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            glowPulsing = true
        }

        // Use holdStartTime to compute progress each tick, avoiding stale capture
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [self] _ in
            guard let start = holdStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            let newProgress = min(CGFloat(elapsed / 3.0), 1.0) // 3 second ramp
            holdProgress = newProgress
            vm.updateHapticIntensity(Float(newProgress))
        }
    }

    private func endHold(_ vm: LogViewModel) {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        vm.stopHaptic()
        let wasHolding = isHolding
        isHolding = false
        withAnimation(.easeOut(duration: 0.25)) {
            glowPulsing = false
        }
        if wasHolding {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
                holdProgress = 0
            }
            logTemptationAction(vm)
        }
    }

    private func cancelHold(_ vm: LogViewModel) {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartTime = nil
        vm.stopHaptic()
        isHolding = false
        didHold = false
        withAnimation(.easeOut(duration: 0.25)) {
            glowPulsing = false
        }
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
            holdProgress = 0
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if habits.isEmpty {
                    emptyStateView
                } else if let vm = viewModel {
                    logContentView(vm)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddHabitSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Habit")
                    .accessibilityIdentifier("addHabitButtonLog")
                }
            }
        }
        .sheet(isPresented: $showAddHabitSheet, onDismiss: {
            if viewModel == nil {
                viewModel = LogViewModel(
                    modelContext: modelContext,
                    defaultHabitId: userSettings.first?.defaultHabitId,
                    locationManager: locationManager
                )
            } else {
                viewModel?.fetchHabits()
            }
        }) {
            AddHabitFromLogSheet(modelContext: modelContext)
        }
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }

            if viewModel == nil {
                let vm = LogViewModel(
                    modelContext: modelContext,
                    defaultHabitId: userSettings.first?.defaultHabitId,
                    locationManager: locationManager
                )
                vm.prepareHaptics()
                viewModel = vm
            } else {
                viewModel?.fetchHabits()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No habits to track")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a habit to start logging temptations.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { showAddHabitSheet = true }) {
                Label("Add Habit", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func logContentView(_ vm: LogViewModel) -> some View {
        let dimAmount = reduceMotion ? 0.0 : holdProgress * 0.5

        ZStack {
            VStack(spacing: 0) {
                // Proportional spacers (~1:2 top:bottom) float the hero cluster
                // near optical center instead of pinning it under the nav title
                // with a dead band above the tab bar.
                Spacer(minLength: 0)
                    .frame(maxHeight: 96)

                // Current habit card cluster — pager sits directly above the
                // card it controls so the relationship reads as one unit.
                if let habit = vm.selectedHabit {
                    if let pattern = vm.activePattern {
                        patternHeadsUp(pattern)
                            .opacity(1.0 - dimAmount)
                            .padding(.bottom, 16)
                    }

                    if vm.habits.count > 1 {
                        habitCarousel(vm)
                            .opacity(1.0 - dimAmount)
                            .padding(.bottom, 16)
                    }

                    // ZStack so the outgoing and incoming cards overlap during the
                    // slide rather than both claiming space in the column. Safe
                    // because every card is the same height — see habitCard.
                    ZStack {
                        habitCard(habit, vm: vm)
                            .id(habit.id)
                            .transition(cardTransition)
                    }
                    .offset(x: cardDragOffset)
                    // The card's own zIndex now only orders it within this stack;
                    // the hold glow still has to sit above the rest of the column.
                    .zIndex(isHolding ? 1 : 0)

                    Label("Tap or hold to log", systemImage: "hand.tap")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .opacity(1.0 - dimAmount)

                    // Context tags (pre-select before logging)
                    if !contextTags.isEmpty {
                        VStack(spacing: 10) {
                            Text("Add context (optional)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)

                            tagChips
                        }
                        .padding(.top, 28)
                        .opacity(1.0 - dimAmount)
                    }
                    // Today's count sits a fixed distance below the chips so it
                    // reads as part of the hero cluster instead of stranding at
                    // the very bottom of the screen.
                    Text("Today: \(habit.todayEventsCount) logged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 28)
                        .opacity(1.0 - dimAmount)
                        .accessibilityLabel("\(habit.todayEventsCount) logged today for \(habit.name)")
                }

                // Larger flexible space below the cluster than above it keeps the
                // composed group centered slightly high, with no low void.
                Spacer(minLength: 0)
            }

            // Dimming vignette behind the card during hold
            if isHolding && !reduceMotion {
                Color.black
                    .opacity(dimAmount * 0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if vm.showConfirmation {
                confirmationBanner(vm: vm)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: vm.showConfirmation)
    }

    /// A quiet line that appears only when the clock is inside one of this
    /// habit's known patterns.
    ///
    /// Being caught off guard is the thing this app is trying to prevent, and
    /// Insights only helps after the fact — the user has to go and look. This is
    /// the same finding delivered at the moment it applies, on the screen they
    /// already open. It states the pattern and stops; no warning, no advice.
    @ViewBuilder
    private func patternHeadsUp(_ pattern: PatternFinder.Pattern) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // calendar.badge.clock, not clock.badge.exclamationmark: the finding
            // is a weekday and an hour, and the app does not raise alarms.
            Image(systemName: "calendar.badge.clock")
                .font(.subheadline)
                .foregroundStyle(accentColor)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                // A label above the finding rather than "This is a usual time —"
                // in front of it. The preamble cost the whole first line before
                // saying anything, and pushed the sentence — the part that has
                // to be read at a glance — down into a wrapped clause.
                Text("Usual time")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(pattern.summary)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            // Rounded rect rather than a capsule: a long pattern sentence wraps
            // to two lines at larger type sizes, and a capsule around two lines
            // reads as a mistake.
            RoundedRectangle(cornerRadius: 14).fill(accentColor.opacity(0.10))
        )
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usual time. \(pattern.summary)")
    }

    @ViewBuilder
    private func habitCarousel(_ vm: LogViewModel) -> some View {
        // One centered natural-width row — chevron · dots · chevron — instead
        // of edge-pinned chevrons with a separate dots row below.
        HStack(spacing: 20) {
            Button(action: { switchHabit(vm, forward: false) }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Previous habit")

            // Habit indicators
            HStack(spacing: 8) {
                ForEach(Array(vm.habits.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(index == vm.selectedHabitIndex ? accentColor : Color(.tertiaryLabel))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Habit \(vm.selectedHabitIndex + 1) of \(vm.habits.count)")

            Button(action: { switchHabit(vm, forward: true) }) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Next habit")
        }
    }

    private func habitCard(_ habit: Habit, vm: LogViewModel) -> some View {
        let habitColor = Color(hex: habit.colorHex ?? "#007AFF") ?? .blue
        // An empty string measures short even under `lineLimit(_:reservesSpace:)`
        // — it reserved ~10pt where two lines want ~41. A single space carries
        // real line metrics and renders as nothing, so a habit with no
        // description gets a card the exact size of one that has a description.
        let rawDescription = habit.habitDescription ?? ""
        let description = rawDescription.isEmpty ? " " : rawDescription
        let cardScale = reduceMotion ? 1.0 : 1.0 + (holdProgress * 0.08)
        let glowPulseIntensity: CGFloat = glowPulsing ? 1.0 : 0.5
        // Resting affordance: a steady habit-color border so the card reads as
        // the primary tappable action (not a passive info panel), and gives the
        // surface figure/ground separation on the pure-black dark canvas. The
        // hold effect's progress/glow rings render on top of this.
        let restBorderOpacity: CGFloat = isHolding ? 0 : 0.55

        // The card is one heavily-decorated view (surface fill, resting border,
        // two hold rings, a radiating ring, layered shadows, scale, accessibility,
        // and gestures). Built as a single fluent chain it overwhelms the Swift
        // type-checker — Xcode 16's solver times out ("unable to type-check this
        // expression in reasonable time"). Splitting it across typed `let`
        // bindings type-checks each sub-expression independently; the resulting
        // view tree is identical.

        // Inner content — icon, name, optional description.
        let content = VStack(spacing: 16) {
            // Icon — gets its own glow during hold. Boxed to a fixed height
            // because SF Symbols don't share a bounding box at a given point
            // size: `sun.max.fill`'s rays make it 3pt taller than `circle.fill`,
            // enough on its own to give two habits differently-sized cards. The
            // box is a constant rather than a scaled value because
            // `.system(size:)` is itself fixed and ignores Dynamic Type. Nothing
            // clips — a taller symbol just overflows into the stack spacing.
            Image(systemName: habit.iconName ?? "circle.fill")
                .font(.system(size: 48))
                .frame(height: 56)
                .foregroundStyle(habitColor)
                .shadow(
                    color: habitColor.opacity(isHolding ? holdProgress * 0.8 : 0),
                    radius: isHolding ? 6 + holdProgress * 14 : 0
                )

            // Name — one line always. A long name scales down rather than
            // wrapping, so it can't add height (see the description note).
            Text(habit.name)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Description — always rendered and always two lines tall, even when
            // absent or one line, because every habit card must be the same size:
            // the card is a swipeable page, and a per-habit height would resize
            // the page mid-slide and shove the rest of the column around. Height
            // comes from the reserved line count, so it still tracks Dynamic Type
            // instead of being pinned to a magic number. Cost: a description over
            // two lines truncates.
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .padding(.horizontal)
        }
        .padding(32)
        .frame(maxWidth: .infinity)

        // Surface fill + resting affordance border.
        let filled = content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        // Background tint intensifies during hold. Resting tint is a
                        // touch stronger than before so the surface separates from
                        // the canvas (notably the pure-black dark background).
                        RoundedRectangle(cornerRadius: 20)
                            .fill(habitColor.opacity(0.15 + holdProgress * 0.2))
                    )
            )
            .overlay(
                // Resting affordance border — steady habit-color stroke that signals
                // the card is the interactive log control and frames the surface.
                RoundedRectangle(cornerRadius: 20)
                    .stroke(habitColor.opacity(restBorderOpacity), lineWidth: 1.5)
            )

        // Hold-progress rings layered on top of the surface.
        let ringed = filled
            .overlay(
                // Progress trim ring — shows exactly how far along the hold is
                RoundedRectangle(cornerRadius: 20)
                    .trim(from: 0, to: holdProgress)
                    .stroke(habitColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .opacity(isHolding ? 1 : 0)
            )
            .overlay(
                // Pulsing glow border — breathes via repeating animation
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        habitColor.opacity(holdProgress * glowPulseIntensity * 0.8),
                        lineWidth: 2 + holdProgress * 3
                    )
                    .blur(radius: 4)
                    .opacity(isHolding ? 1 : 0)
            )

        // Radiating ring behind the card + layered shadow glow + scale.
        let glowing = ringed
            // Radiating pulse ring — expands outward and fades (Hacking with Swift pattern)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(habitColor.opacity(0.4), lineWidth: 2)
                    .scaleEffect(isHolding && !reduceMotion ? 1.0 + holdProgress * 0.15 : 1.0)
                    .opacity(isHolding ? Double(1.0 - holdProgress) * 0.6 : 0)
            )
            // Layered shadow glow — tight inner + wide outer, pulse-modulated
            .shadow(
                color: habitColor.opacity(isHolding ? holdProgress * glowPulseIntensity * 0.5 : 0),
                radius: isHolding ? 12 + holdProgress * 16 : 0
            )
            .shadow(
                color: habitColor.opacity(isHolding ? holdProgress * glowPulseIntensity * 0.25 : 0),
                radius: isHolding ? 30 + holdProgress * 30 : 0
            )
            .scaleEffect(cardScale)
            .animation(reduceMotion ? .none : .easeOut(duration: 0.15), value: cardScale)
            .zIndex(isHolding ? 1 : 0)

        // Accessibility + gesture wiring as the final, lighter chain.
        return glowing
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Log temptation for \(habit.name)")
            .accessibilityValue("\(habit.todayEventsCount) logged today")
            .accessibilityHint("Tap or hold to log a temptation")
            .accessibilityAddTraits(.isButton)
            // VoiceOver users can't perform the swipe-to-switch-habit drag, so expose
            // the carousel's next/previous as named actions on the card itself (the
            // visible arrows are also labelled, but only render with >1 habit).
            .accessibilityActions {
                if vm.habits.count > 1 {
                    Button("Next habit") { switchHabit(vm, forward: true) }
                    Button("Previous habit") { switchHabit(vm, forward: false) }
                }
            }
            .padding(.horizontal, 24)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .onTapGesture {
                // Only handle tap if the drag gesture didn't trigger a hold
                if !didHold {
                    logTemptationAction(vm)
                }
                didHold = false
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let distance = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)

                        if distance > 30 {
                            // User is swiping — drop the armed (or running) hold
                            // before any of its visuals or haptics engage.
                            if holdStartTime != nil {
                                cancelHold(vm)
                            }
                            cardDragOffset = value.translation.width * 0.4
                        } else if holdStartTime == nil && distance < 10 {
                            // Finger staying still — arm the hold
                            armHold(vm)
                        }
                    }
                    .onEnded { value in
                        let distance = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)

                        if distance > 30 {
                            // Swipe gesture ended — cancel any hold state
                            didHold = false
                            // Commit on predicted end translation, which folds in
                            // release velocity: a fast flick travels little before
                            // liftoff, so gating on raw translation left a 30–50pt
                            // dead band where the card animated but never switched.
                            let dx = value.predictedEndTranslation.width
                            if abs(dx) > 50 {
                                switchHabit(vm, forward: dx < 0)
                            } else if reduceMotion {
                                cardDragOffset = 0
                            } else {
                                // Not far enough — snap back, same habit.
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    cardDragOffset = 0
                                }
                            }
                        } else if isHolding {
                            // Hold released — log temptation
                            endHold(vm)
                        } else {
                            // Lifted before the hold armed (a tap) — kill the
                            // pending arm timer so it can't start a hold with no
                            // finger down. onTapGesture still does the logging.
                            cancelHold(vm)
                        }
                    }
            )
            .onDisappear {
                // Clean up timer if view disappears mid-hold
                holdTimer?.invalidate()
                holdTimer = nil
                holdStartTime = nil
            }
            // No implicit animation on cardDragOffset: a spring between the finger
            // and the card lags direct manipulation (and fought the explicit
            // release spring in onEnded). Drag tracks 1:1; only the snap animates.
    }

    @ViewBuilder
    private func confirmationBanner(vm: LogViewModel) -> some View {
        let outcome = vm.lastLoggedEvent?.outcomeEnum ?? .resisted
        let didGiveIn = outcome == .gaveIn

        HStack(spacing: 12) {
            // Status group (combined accessibility element, no button trait)
            HStack(spacing: 8) {
                Image(systemName: didGiveIn ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(outcome.color)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                Text(didGiveIn ? TemptationEvent.Outcome.gaveIn.displayName : "Logged")
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .id(outcome)
                    .transition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(didGiveIn ? TemptationEvent.Outcome.gaveIn.displayName : "Logged")

            Spacer()

            // Controls group (trailing)
            HStack(spacing: 0) {
                if !didGiveIn {
                    Button {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                            vm.markLastLogGaveIn()
                        }
                        UIAccessibility.post(notification: .announcement, argument: "Outcome changed to gave in")
                    } label: {
                        Text("Gave in")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TemptationEvent.Outcome.gaveIn.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Gave in")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Changes this log's outcome to gave in.")
                    .transition(.opacity)

                    Divider()
                        .frame(height: 20)
                        .transition(.opacity)
                }

                Button {
                    vm.undoLastLog()
                } label: {
                    Text("Undo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Undo last log")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Deletes this log.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var tagChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(contextTags) { tag in
                let isSelected = selectedTagNames.contains(tag.name)
                Button {
                    if isSelected {
                        selectedTagNames.remove(tag.name)
                    } else {
                        selectedTagNames.insert(tag.name)
                    }
                } label: {
                    Text(tag.name)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                // Semantic fill (not a fixed translucent gray) so
                                // the unselected chip keeps adequate presence in
                                // both light and dark mode rather than fading into
                                // the pure-black dark canvas.
                                .fill(isSelected ? accentColor : Color(.secondarySystemFill))
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .accessibilityLabel(tag.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Quick Add Habit Sheet (from Log empty state)

private struct AddHabitFromLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext

    @State private var name = ""
    @State private var description = ""
    @State private var selectedColor = HabitsViewModel.availableColors[0].hex
    @State private var selectedIcon = HabitsViewModel.availableIcons[0]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Habit name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(HabitsViewModel.availableColors, id: \.hex) { color in
                            Circle()
                                .fill(Color(hex: color.hex) ?? .blue)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color.hex ? 3 : 0)
                                )
                                .onTapGesture { selectedColor = color.hex }
                                .accessibilityLabel(color.name)
                                .accessibilityAddTraits(selectedColor == color.hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Icon") {
                    let iconColor = Color(hex: selectedColor) ?? .blue
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                        ForEach(HabitsViewModel.availableIcons, id: \.self) { icon in
                            let isSelected = selectedIcon == icon
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundStyle(isSelected ? iconColor : Color.primary)
                                .frame(width: 50, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? iconColor.opacity(0.2) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? iconColor : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { selectedIcon = icon }
                                .accessibilityLabel(icon.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                                .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let habit = Habit(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            habitDescription: description.isEmpty ? nil : description,
                            colorHex: selectedColor,
                            iconName: selectedIcon,
                            sortOrder: Habit.nextSortOrder(in: modelContext)
                        )
                        modelContext.insert(habit)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

#Preview {
    LogView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
}
