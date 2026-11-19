import SwiftUI

/// The popover's battery gauge. It is the shared `BatteryGauge`, so the popover and the widgets draw the same gauge:
/// the fill is what is left, in the tier colour, and an account with no limit draws an empty gauge.
struct LocalBatteryGauge: View {
    let usedPercent: Double?

    var body: some View {
        BatteryGauge(usedPercent: usedPercent)
    }
}
