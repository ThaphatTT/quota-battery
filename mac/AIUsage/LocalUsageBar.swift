import SwiftUI

/// A thin rounded bar. The fill springs from the old length to the new one.
struct LocalUsageBar: View {
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
