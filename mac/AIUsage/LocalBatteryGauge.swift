import SwiftUI

/// The popover's battery gauge. With still motion it is the shared `BatteryGauge`, which the widgets also use, so the
/// widgets stay as they are. With live motion the fill is a damped spring: it moves on a value change, and on the first
/// opening of the popover in the app session it grows from empty (`growKey`).
struct LocalBatteryGauge: View {
    let usedPercent: Double?
    /// Set once per app session to grow the fill on its first showing. Nil: no first-open growth.
    var growKey: String?
    var growDelay: Double = 0
    @Environment(\.motionLevel) private var motion

    var body: some View {
        if motion == .live {
            LiveBatteryGauge(usedPercent: usedPercent, growKey: growKey, growDelay: growDelay)
        } else {
            BatteryGauge(usedPercent: usedPercent)
        }
    }
}

private struct LiveBatteryGauge: View {
    let usedPercent: Double?
    let growKey: String?
    let growDelay: Double
    @Environment(\.colorScheme) private var colorScheme
    @State private var spring: LiquidSpring?
    @State private var tick = 0

    var body: some View {
        let size = CGSize(width: 24, height: 11)
        let tier = UsageFormat.tier(usedPercent)
        let outline = tier == .critical ? tier.color(colorScheme) : UsageTheme.outline
        let inset: CGFloat = 2
        let inner = size.width - 2 * inset
        let fraction = min(max(spring?.position ?? UsageFormat.remainingFraction(usedPercent), 0), 1)
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: size.height * 0.3, style: .continuous)
                    .stroke(outline, lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tier.color(colorScheme))
                    .frame(
                        width: UsageFormat.fillWidth(fraction: fraction, available: inner),
                        height: size.height - 2 * inset
                    )
                    .padding(.leading, inset)
            }
            .frame(width: size.width, height: size.height)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(outline)
                .frame(width: 1.5, height: size.height * 0.4)
        }
        // Reads the tick, so each frame of the spring draws the new fill.
        .animation(nil, value: tick)
        .task(id: UsageFormat.remainingFraction(usedPercent)) {
            let target = UsageFormat.remainingFraction(usedPercent)
            if let growKey, FirstOpenTracker.shared.claim("gauge." + growKey) {
                spring = LiquidSpring(position: 0, target: target, startAt: Date().addingTimeInterval(growDelay))
            } else if spring == nil {
                spring = LiquidSpring(position: target, target: target)
            }
            spring?.setTarget(target)
            await MotionLoop.run {
                spring?.advance(to: Date())
                tick &+= 1
                return !(spring?.isSettled ?? true)
            }
        }
    }
}
