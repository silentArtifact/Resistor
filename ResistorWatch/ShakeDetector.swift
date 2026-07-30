import CoreMotion
import Foundation

/// Detects a deliberate wrist shake, used to undo a just-logged temptation.
///
/// watchOS has no shake gesture: UIKit's `UIEventSubtype.motionShake` is
/// iOS-only and `WKInterfaceDevice` exposes nothing equivalent, so this reads
/// Core Motion directly.
///
/// A shake is `requiredSpikes` direction reversals inside a `window`. A reversal
/// is counted as a *rising edge* — magnitude climbing past `threshold` after
/// having dropped below `releaseThreshold` — not merely as a sample above the
/// threshold. That distinction is the whole defence against false positives: one
/// hard knock is a single sustained peak spanning many samples, so it produces
/// exactly one edge, while a real shake passes back through near-zero at every
/// change of direction.
///
/// Reads `CMDeviceMotion.userAcceleration`, not the raw accelerometer: device
/// motion has already subtracted gravity, so raising, lowering, or rotating the
/// wrist reads near zero. A raw accelerometer would see a constant 1g and every
/// reorientation as a large delta.
///
/// Only runs while an undo is actually offered — the sensor is expensive to
/// leave on, and a shake means nothing outside that window.
final class ShakeDetector {

    /// Magnitude, in g, that arms a spike. A deliberate shake crosses 2g
    /// comfortably; an arm drop or wrist turn stays well under.
    ///
    /// ponytail: fixed thresholds, no per-user calibration. These are the knobs
    /// to turn if it misfires or feels unresponsive on a real wrist — sensor
    /// tuning can't be settled from a desk.
    private let threshold: Double = 2.0
    /// Magnitude the motion must fall back below before the next spike can be
    /// counted. Deliberately far below `threshold`: releasing at the same level it
    /// armed would let sensor noise hovering around 2g chatter out spikes that
    /// never corresponded to a real reversal. (A Schmitt trigger, in short.)
    private let releaseThreshold: Double = 0.8
    /// How long spikes stay eligible to combine into a shake.
    private let window: TimeInterval = 1.2
    /// Direction reversals needed. Two would fire on a single hard flick.
    private let requiredSpikes = 3

    private let motion = CMMotionManager()
    /// `CMDeviceMotion.timestamp` — seconds since boot, monotonic, and immune to
    /// the wall clock moving under us.
    private var spikeTimes: [TimeInterval] = []
    /// Edge-detector state: true while the current peak is still above
    /// `releaseThreshold`, so its samples don't each count as a spike.
    private var isAboveThreshold = false
    private var onShake: (() -> Void)?

    var isRunning: Bool { motion.isDeviceMotionActive }

    /// Starts listening. `onShake` is called on the main queue once per
    /// `requiredSpikes` reversals — so a long, vigorous shake fires more than
    /// once, and **the caller must `stop()` in response** if it wants exactly one
    /// action. `WatchLogView.performUndo` does, synchronously; since updates are
    /// delivered on `.main`, no further sample can arrive in between.
    func start(onShake: @escaping () -> Void) {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        self.onShake = onShake
        spikeTimes.removeAll()
        isAboveThreshold = false
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            handle(motion)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        onShake = nil
        spikeTimes.removeAll()
        isAboveThreshold = false
    }

    private func handle(_ motion: CMDeviceMotion) {
        let a = motion.userAcceleration
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        if register(magnitude: magnitude, at: motion.timestamp) {
            onShake?()
        }
    }

    /// The whole decision, split out from `CMDeviceMotion` so it can be tested:
    /// `CMDeviceMotion` has no public initialiser, so a test can't feed the
    /// handler above a synthetic shake. Returns `true` on the sample that
    /// completes one.
    ///
    /// Not private — `ShakeDetectorTests` drives it directly.
    func register(magnitude: Double, at time: TimeInterval) -> Bool {
        // Still riding the peak that armed the last spike. Nothing new can be
        // counted until the motion actually dies down — otherwise one sustained
        // jolt walks the spike count up a sample at a time.
        if isAboveThreshold {
            if magnitude < releaseThreshold { isAboveThreshold = false }
            return false
        }

        guard magnitude > threshold else { return false }
        isAboveThreshold = true

        spikeTimes.append(time)
        spikeTimes.removeAll { time - $0 > window }

        guard spikeTimes.count >= requiredSpikes else { return false }
        // Consume the spikes so the shake fires once, not again on every sample
        // of the tail end of the same motion.
        spikeTimes.removeAll()
        return true
    }
}
