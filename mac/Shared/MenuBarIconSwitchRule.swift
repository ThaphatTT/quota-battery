/// What the "show menu bar icon" switch asks of the status item. The rule is pure, so the guard is tested without AppKit,
/// and the app runs the same rule.
///
/// `isVisible` is set only when the switch's value differs from the one applied last, and never while `isVisible` is
/// being set. Setting it makes AppKit write its own defaults, and that must not start the rule again.
enum MenuBarIconSwitchRule {
    enum Step: Equatable {
        /// Nothing to do.
        case nothing
        /// The switch changed, but the item already shows the new value: only remember it.
        case rememberOnly
        /// The switch changed and the item shows the other value: remember it, then set `isVisible`.
        case setVisible(Bool)
    }

    /// - Parameters:
    ///   - wanted: The stored value of the switch, true when missing.
    ///   - lastApplied: The value handled last time, or nil before the first look at launch.
    ///   - isVisibleNow: The item's `isVisible` at this moment.
    ///   - isApplying: True while `isVisible` is being set.
    static func step(wanted: Bool, lastApplied: Bool?, isVisibleNow: Bool, isApplying: Bool) -> Step {
        guard !isApplying else { return .nothing }
        guard wanted != lastApplied else { return .nothing }
        return isVisibleNow == wanted ? .rememberOnly : .setVisible(wanted)
    }
}
