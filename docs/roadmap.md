# Resistor — Development Roadmap

Step-by-step guide from current state to App Store submission.

**Last updated:** 2026-04-10

---

## Phase 1: Ship-Ready Code

Everything needed before the first TestFlight build. These are code and configuration tasks.

### ~~1.1 Commit CloudKit schema fix~~ Done
- Committed in `79d7e35`. All three models have property-level defaults and optional relationships.

### ~~1.2 Update design.md tip jar section~~ Done
- Committed in `eba0cc9`. Updated to single $1.99 tip.

### ~~1.3 Fix "Gave In" outcome color~~ Done
- Committed in `fd25253`. Changed from `.red` to `.orange`.

### ~~1.4 Close resolved GitHub issues~~ Done
- **#35 (App icon):** Still open — no image file exists yet. Requires design work.
- **#36 (Dark mode audit):** Closed. Code fixes in `87ee348`, remaining items are on-device verification during Phase 2 QA.
- **#37 (Accessibility pass):** Closed. Code fixes in `87ee348`, remaining items are on-device VoiceOver walkthrough during Phase 2 QA.

### ~~1.5 Verify CI simulator target~~ No change needed
- CI uses iPhone 16 Pro (macos-15 / Xcode 16.4) — correct for the GitHub runner.
- Local builds use iPhone 17 Pro (iOS 26) — correct for development machine.
- Different environments, both appropriate.

---

## Phase 2: TestFlight

Manual steps in Xcode and App Store Connect. Requires Apple Developer account.

### 2.1 Xcode project configuration
- Set team ID and signing certificate
- Confirm bundle ID (`com.resistor.app` or equivalent)
- Verify CloudKit container is created and linked
- Set version to `0.1.0`, build number `1`

### 2.2 iCloud sync testing
- Build to physical device (iPhone 16 Pro)
- Create habits and log events on device
- Confirm data appears on a second device or simulator via iCloud
- Verify sync within 30 seconds on Wi-Fi (quality gate from design spec)
- Test conflict scenarios: log on two devices while one is offline

### 2.3 Manual QA pass
- Full onboarding flow on clean install
- Log 50+ temptations without crash (quality gate)
- Verify log action < 100ms (quality gate)
- Export data, verify JSON is valid
- Delete all data, verify clean slate
- Archive/unarchive habits
- Switch accent colors
- Test in both dark and light mode
- Test with Dynamic Type at largest size

### 2.4 Upload to TestFlight
- Archive in Xcode
- Upload to App Store Connect
- Add testers (Matt + 3-4 friends per design spec)
- Include brief test instructions

### 2.5 Gather feedback
- Run TestFlight for minimum 2 weeks
- Track: daily usage consistency, outcome completion rate, crash reports
- Address critical bugs immediately, collect feature feedback for post-v1

---

## Phase 3: App Store Submission

Everything needed after TestFlight feedback is addressed.

### 3.1 Privacy policy
- Required for App Store submission
- Host as a simple web page (GitHub Pages, static site, etc.)
- Content: what data is collected (habits, events, timestamps), iCloud sync, no analytics, no third-party sharing
- Add URL to App Store Connect and optionally in-app

### 3.2 App Store metadata
- **Name:** Resistor
- **Subtitle:** Track temptations, see patterns.
- **Category:** Health & Fitness
- **Price:** Free
- **Keywords:** temptation, habit, tracker, urge, resist, impulse, pattern, behavior, self-control, log
- Write description (short + long)
- Capture screenshots on iPhone 16 Pro (or required device set)
- Prepare promotional text

### 3.3 Address TestFlight feedback
- Fix any bugs reported during testing
- Adjust UX friction points based on tester feedback
- Do NOT add new features — save for v1.1

### 3.4 Final quality gates
- All tests pass
- Accessibility audit clean (VoiceOver full walkthrough)
- Dark/light mode clean
- Export works
- 2 weeks of personal daily use completed
- No crashes in testing period

### 3.5 Configure tip jar in App Store Connect
- Create consumable IAP product (`com.resistor.tip`, $1.99)
- Add IAP metadata (display name, description)
- Submit for review alongside app

### 3.6 Submit for review
- Set version to `1.0.0`
- Submit app + IAP for Apple review
- Respond to any review feedback

---

## Post-v1 (Reference)

From `docs/design.md` — not part of this roadmap, listed for context.

- **v1.1:** Location clustering, iPad support
- **v1.2:** Home screen widget, Apple Watch app
- **Future:** Custom context tags, intensity trends, weekly summaries, import, Siri Shortcuts
