import SwiftUI

/// A small ring that fills clockwise from the top. With no data it is a dashed, hollow ring.
struct LocalUsageRing: View {
    /// 0 to 1, or nil when there is no data.
    let progress: Double?
    let tint: Color
    var size: CGFloat = 12
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            if let progress {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(tint.opacity(0.3), lineWidth: lineWidth)
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(tint.opacity(0.7), style: StrokeStyle(lineWidth: lineWidth, dash: [2, 2]))
            }
        }
        .frame(width: size, height: size)
    }
}
