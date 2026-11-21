import SwiftUI

/// A thin rounded bar that draws its value at once and springs between values, as it did before the first-open motion.
/// Used for still draws (snapshots, Reduce Motion). The live bar is `LiveUsageBar`; `usageBar` picks one.
struct StillUsageBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .animation(LocalMotion.spring(reduced: reduceMotion), value: fraction)
    }
}

/// The usage bar of a card or a row. With live motion it is `LiveUsageBar`: a damped spring that overshoots a little and
/// ripples with its speed, grows from empty on the first showing (when `growKey` is set), and stops when it settles.
/// With still motion it is `StillUsageBar`, which has no state and no motion loop.
@ViewBuilder
func usageBar(
    fraction: Double, color: Color, height: CGFloat = 6, growKey: String? = nil, growDelay: Double = 0, motion: MotionLevel
) -> some View {
    if motion == .live {
        LiveUsageBar(fraction: fraction, color: color, height: height, growKey: growKey, growDelay: growDelay)
    } else {
        StillUsageBar(fraction: fraction, color: color, height: height)
    }
}

/// The live usage bar: the spring for the fill, the first-open growth, and the frames while it moves.
struct LiveUsageBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6
    var growKey: String?
    var growDelay: Double = 0
    @State private var spring: LiquidSpring?
    /// Changes on every frame, so the view draws the spring's new position.
    @State private var tick = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                LiquidFill(position: spring?.position ?? fraction, velocity: spring?.velocity ?? 0, color: color, phase: Double(tick))
            }
        }
        .frame(height: height)
        .task(id: fraction) {
            if let growKey, FirstOpenTracker.shared.claim("bar." + growKey) {
                spring = LiquidSpring(position: 0, target: fraction, startAt: Date().addingTimeInterval(growDelay))
            } else if spring == nil {
                spring = LiquidSpring(position: fraction, target: fraction)
            }
            spring?.setTarget(fraction)
            await MotionLoop.run {
                spring?.advance(to: Date())
                tick &+= 1
                return !(spring?.isSettled ?? true)
            }
        }
    }
}

/// The filled part of a live bar: a capsule whose right edge bulges with the spring's speed. Clipped to the capsule.
struct LiquidFill: View {
    let position: Double
    let velocity: Double
    let color: Color
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let width = size.width * min(max(position, 0), 1.02)
            let ripple = min(4, abs(velocity) * 2)
            var path = Path()
            path.move(to: .zero)
            let rows = 12
            for row in 0...rows {
                let y = size.height * CGFloat(row) / CGFloat(rows)
                let bulge = ripple * sin(phase * 0.8 + Double(row) * 0.9)
                path.addLine(to: CGPoint(x: width + CGFloat(bulge), y: y))
            }
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
        .clipShape(Capsule())
    }
}
