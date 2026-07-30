import XCTest
@testable import Resistor

/// Tests the shake-to-undo decision logic on the watch Quick-Log screen.
///
/// Unlike `WatchLogStoreLogicTests`, which must duplicate the watch algorithm
/// because `WatchLogStore` depends on `WatchModelContainer`, `ShakeDetector` has
/// no watch-only dependency — Core Motion exists on iOS — so
/// `ResistorWatch/ShakeDetector.swift` is compiled directly into this test
/// bundle and these tests exercise the real implementation.
///
/// `register(magnitude:at:)` is the whole decision, split out from the
/// `CMDeviceMotion` handler precisely so it can be driven here:
/// `CMDeviceMotion` has no public initialiser, so a synthetic shake cannot be
/// fed through the sensor callback.
///
/// NOT covered (hardware only): whether a real wrist shake clears 2g, whether an
/// arm drop stays under it, and whether `startDeviceMotionUpdates` delivers on a
/// watch without a usage-description prompt.
final class ShakeDetectorTests: XCTestCase {

    /// Above the 2g arming threshold.
    private let spike = 2.5
    /// Below the 0.8g release threshold — where a real shake passes through at
    /// every change of direction.
    private let calm = 0.4
    /// Spacing between reversals of a brisk shake.
    private let step: TimeInterval = 0.15

    /// Feeds samples and returns the times at which a shake fired.
    private func fire(_ detector: ShakeDetector, _ samples: [(Double, TimeInterval)]) -> [TimeInterval] {
        samples.compactMap { magnitude, time in
            detector.register(magnitude: magnitude, at: time) ? time : nil
        }
    }

    /// `count` direction reversals starting at `start`: each is a peak with a
    /// return through near-zero after it, which is what the accelerometer
    /// actually reports for a shake.
    private func reversals(_ count: Int, from start: TimeInterval = 0) -> [(Double, TimeInterval)] {
        (0..<count).flatMap { index -> [(Double, TimeInterval)] in
            let at = start + TimeInterval(index) * step
            return [(spike, at), (calm, at + step / 2)]
        }
    }

    // MARK: - Firing

    func testThreeReversalsFireOnce() {
        let detector = ShakeDetector()
        let fired = fire(detector, reversals(3))
        XCTAssertEqual(fired, [step * 2], "Fires on the third reversal, and only then")
    }

    /// The detector fires per three reversals, so a long shake fires repeatedly.
    /// That is the primitive's contract, NOT a licence for `performUndo` to delete
    /// two events: the caller stops the detector on the first fire, and because
    /// samples are delivered on the main queue, `stop()` lands before another one
    /// can arrive. This test pins the contract so the caller's obligation stays
    /// visible.
    func testLongShakeFiresPerThreeReversalsSoTheCallerMustStop() {
        let detector = ShakeDetector()
        XCTAssertEqual(fire(detector, reversals(6)).count, 2,
                       "Six reversals is two groups of three — the caller is what makes it one undo")

        // What the caller actually does: `stop()` halts sensor delivery, so no
        // further sample reaches `register` at all. (A sample already queued on
        // `.main` when stop lands is harmless too — `stop()` nils `onShake`.)
        let stopping = ShakeDetector()
        var undos = 0
        for (magnitude, time) in reversals(6) {
            guard stopping.register(magnitude: magnitude, at: time) else { continue }
            undos += 1
            stopping.stop()
            break
        }
        XCTAssertEqual(undos, 1, "Stopping delivery on the first fire yields exactly one undo")
    }

    // MARK: - Not firing

    func testTwoReversalsDoNotFire() {
        let detector = ShakeDetector()
        XCTAssertTrue(fire(detector, reversals(2)).isEmpty, "Two reversals is a flick, not a shake")
    }

    func testSubThresholdMotionNeverFires() {
        let detector = ShakeDetector()
        // An arm drop: sustained motion that never crosses the arming threshold.
        let samples = (0..<40).map { (1.9, TimeInterval($0) * 0.02) }
        XCTAssertTrue(fire(detector, samples).isEmpty,
                      "Motion below the threshold must never undo a log")
    }

    /// The regression this whole edge-detector exists for. A knock is ONE peak
    /// spanning many 50Hz samples; counting samples-above-threshold spaced in time
    /// (rather than rising edges) fired a shake on it, which would have undone a
    /// log the user meant to keep.
    func testOneSustainedPeakDoesNotFire() {
        let detector = ShakeDetector()
        // 0.4s continuously above threshold, never returning to calm.
        let samples = (0..<20).map { (3.0, TimeInterval($0) * 0.02) }
        XCTAssertTrue(fire(detector, samples).isEmpty,
                      "A single sustained peak is one reversal, however long it lasts")
    }

    /// Noise hovering just around the arming threshold must not chatter out
    /// spikes — that is what the lower release threshold buys.
    func testChatterAroundTheThresholdDoesNotFire() {
        let detector = ShakeDetector()
        let samples = (0..<40).map { index in
            (index.isMultiple(of: 2) ? 2.1 : 1.9, TimeInterval(index) * 0.02)
        }
        XCTAssertTrue(fire(detector, samples).isEmpty,
                      "Dipping to 1.9g is not a reversal; the motion must fall below 0.8g")
    }

    func testReversalsSpreadBeyondTheWindowDoNotFire() {
        let detector = ShakeDetector()
        // 0.6s apart: three reversals, but the first ages out of the 1.2s window
        // before the third lands.
        let samples: [(Double, TimeInterval)] = [
            (spike, 0.0), (calm, 0.1),
            (spike, 0.6), (calm, 0.7),
            (spike, 1.3), (calm, 1.4)
        ]
        XCTAssertTrue(fire(detector, samples).isEmpty, "Reversals must fall inside the window together")
    }

    // MARK: - Re-arming

    /// Firing consumes its spikes, so the tail of the same shake can't immediately
    /// fire again — which, wired to undo, would delete an event the user never
    /// logged.
    func testDoesNotRefireOnTheTailOfTheSameShake() {
        let detector = ShakeDetector()
        let fired = fire(detector, reversals(3) + [(spike, 0.5), (calm, 0.55)])
        XCTAssertEqual(fired, [step * 2], "The tail needs a fresh three reversals")
    }

    func testFiresAgainAfterASeparateShake() {
        let detector = ShakeDetector()
        let first = fire(detector, reversals(3))
        let second = fire(detector, reversals(3, from: 10.0))
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1, "A later, separate shake still fires")
    }
}
