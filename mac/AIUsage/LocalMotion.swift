import SwiftUI

/// Motion rules for the app. With Reduce Motion on, values fade instead of springing, pulsing or spinning.
enum LocalMotion {
    static func spring(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.8)
    }

    /// First-open rows: a fade (and an 8 pt slide up, drawn by the row), about 0.3 s, each row 60 ms after the one above it.
    /// Reduce Motion: a 0.2 s cross-fade, all rows at once.
    static func rowReveal(index: Int, reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3).delay(Double(index) * 0.06)
    }

}

/// Pulses once, the first time the value reaches 80% used, when it turns yellow. Reduce Motion keeps the colour change and skips the scale.
struct AlertPulse: ViewModifier {
    let isAlert: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulses = 0

    func body(content: Content) -> some View {
        content
            .onChange(of: isAlert) { old, new in
                if new && !old { pulses += 1 }
            }
            .keyframeAnimator(initialValue: CGFloat(1), trigger: pulses) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(reduceMotion ? 1 : 1.06, duration: 0.18)
                    CubicKeyframe(1, duration: 0.32)
                }
            }
    }
}
