import SwiftUI

/// How much a view may move. `still` draws the final state at once: snapshots and Reduce Motion. `live` runs the
/// first-open motion and the value motion of the app.
enum MotionLevel: Equatable {
    case still
    case live

    static func resolve(reduceMotion: Bool, snapshot: Bool) -> MotionLevel {
        reduceMotion || snapshot ? .still : .live
    }
}

/// How a container (the window's cards, the popover's rows, the Accounts rows) enters on its first appearance in the app
/// session. `none` shows the content at once: a later appearance, or a snapshot.
enum IntroStyle: Equatable {
    case none
    /// Reduce Motion: a cross-fade only, no slide, no growing bars, no typing.
    case fade
    /// Fade in and slide up 8 pt, staggered per item.
    case slide

    /// The style for a container's first appearance. Only the first time per view id plays, and never in a snapshot.
    static func resolve(isFirst: Bool, reduceMotion: Bool, snapshot: Bool) -> IntroStyle {
        guard isFirst, !snapshot else { return .none }
        return reduceMotion ? .fade : .slide
    }
}

/// Remembers which views have already played their first-open motion in this app session. It lives in memory only: a new
/// launch plays again. A view asks once when it first shows content; the answer is `true` only the first time.
@MainActor
final class FirstOpenTracker {
    static let shared = FirstOpenTracker()
    private var seen: Set<String> = []

    /// True the first time `id` is asked for, false after that.
    func claim(_ id: String) -> Bool {
        seen.insert(id).inserted
    }

}

@MainActor
final class DesktopPopoverPresentation: ObservableObject {
    enum Phase: Equatable { case hidden, opening, open, closing }
    enum Action: Equatable { case mount, dismiss, reverseDismissal }

    static let duration: TimeInterval = 0.12
    @Published private(set) var phase: Phase = .hidden

    var isRevealed: Bool { phase == .open }

    func toggle() -> Action {
        switch phase {
        case .hidden:
            phase = .opening
            return .mount
        case .opening, .open:
            phase = .closing
            return .dismiss
        case .closing:
            phase = .open
            return .reverseDismissal
        }
    }

    func didShow() {
        if phase == .opening { phase = .open }
    }

    func beginClosing() -> Bool {
        guard phase == .opening || phase == .open else { return false }
        phase = .closing
        return true
    }

    func reset() { phase = .hidden }
}

/// Whether the first usage.json read has finished. Until it has, the views show a skeleton, not "no data". A later read,
/// a refresh or a poll never returns to loading.
enum LoadPhase: Equatable {
    case loading
    case loaded

    var isLoaded: Bool { self == .loaded }

    mutating func finishFirstRead() {
        self = .loaded
    }
}

/// The skeleton's shimmer. It runs only while a skeleton is on screen and the motion is live; once the content has
/// replaced the skeleton, nothing shimmers.
enum SkeletonShimmer {
    /// One sweep of the shimmer, in seconds.
    static let period: Double = 1.2

    static func isRunning(loading: Bool, motion: MotionLevel) -> Bool {
        loading && motion == .live
    }
}

/// Runs a motion frame by frame until the frame says it is done. The loop is counted while it runs, so a test can prove
/// that no motion is left running once everything has settled. It stops when its task is cancelled (the view is gone).
@MainActor
enum MotionLoop {
    /// How many loops are running now.
    private(set) static var active = 0

    static func run(interval: Duration = .milliseconds(16), frame: @escaping @MainActor () -> Bool) async {
        active += 1
        defer { active -= 1 }
        while !Task.isCancelled {
            guard frame() else { return }
            try? await Task.sleep(for: interval)
        }
    }
}

/// A damped spring for a bar's fill, in fractions of the bar (0 to 1). It overshoots a little and settles. It only moves
/// when it is asked to: `isSettled` is true once it rests on its target, and then no frame is needed.
final class LiquidSpring {
    private(set) var position: Double
    private(set) var velocity = 0.0
    private(set) var target: Double
    /// The motion does not begin before this moment (the stagger). Nil once it has begun.
    private var startAt: Date?
    private var last: Date?

    static let stiffness = 170.0
    static let damping = 16.0

    init(position: Double, target: Double, startAt: Date? = nil) {
        self.position = position
        self.target = Self.clamped(target)
        self.startAt = startAt
    }

    var isSettled: Bool {
        abs(target - position) < 0.0005 && abs(velocity) < 0.002
    }

    func setTarget(_ value: Double) {
        target = Self.clamped(value)
    }

    /// Starts again from `position`, after `delay` seconds from `date`. Used when a bar first shows its value.
    func restart(from position: Double, startAt date: Date) {
        self.position = position
        velocity = 0
        last = nil
        startAt = date
    }

    /// Moves the spring up to `date`. Returns the new position. Time steps are capped, so a stalled frame cannot blow up.
    @discardableResult
    func advance(to date: Date) -> Double {
        if let startAt {
            if date < startAt { return position }
            self.startAt = nil
            last = nil
        }
        guard let previous = last else {
            last = date
            return position
        }
        let elapsed = min(max(date.timeIntervalSince(previous), 0), 1.0 / 30.0)
        last = date
        let steps = 4
        let step = elapsed / Double(steps)
        for _ in 0..<steps {
            let acceleration = -Self.stiffness * (position - target) - Self.damping * velocity
            velocity += acceleration * step
            position += velocity * step
        }
        if isSettled {
            position = target
            velocity = 0
            last = nil
        }
        return position
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }
}

/// Counts a number from its shown value to a new one over 0.6 s, ease-out.
enum RollingPlan {
    static let duration = 0.6

    /// The value `elapsed` seconds into a count from `from` to `to`.
    static func value(from: Double, to: Double, elapsed: Double) -> Double {
        let t = min(max(elapsed / duration, 0), 1)
        return from + (to - from) * (1 - pow(1 - t, 3))
    }
}

/// Typing: label text appears one character each 45 ms on a view's first appearance.
enum TypingPlan {
    static let perCharacter = 0.045

    static func visibleCount(total: Int, elapsed: Double) -> Int {
        guard elapsed > 0, total > 0 else { return 0 }
        return min(total, Int(elapsed / perCharacter) + 1)
    }
}

/// The slot-machine brand letter: the strip of letters rolls down and lands on the brand letter with a small overshoot,
/// in about 0.9 s.
enum SlotPlan {
    static let duration = 0.9
    /// The letters rolled past before the brand letter. The strip is these, the brand letter and one more copy of it, so
    /// the overshoot shows the brand letter again and never a gap.
    static let fillers = ["Q", "X", "M", "R", "K"]

    static func strip(letter: String) -> [String] {
        fillers + [letter, letter]
    }

    /// The strip position (in letter heights) at `progress` 0 to 1. It ends on the brand letter at `count - 2`, and
    /// overshoots a little past it on the way (ease-out back).
    static func position(progress: Double, count: Int) -> Double {
        let t = min(max(progress, 0), 1)
        let s = 1.2
        let eased = 1 + (s + 1) * pow(t - 1, 3) + s * pow(t - 1, 2)
        return eased * Double(max(count - 2, 0))
    }
}

/// The environment values the containers set: the motion level of the live app, and the intro style of the container.
private struct MotionLevelKey: EnvironmentKey {
    static let defaultValue: MotionLevel = .still
}

extension EnvironmentValues {
    var motionLevel: MotionLevel {
        get { self[MotionLevelKey.self] }
        set { self[MotionLevelKey.self] = newValue }
    }
}
