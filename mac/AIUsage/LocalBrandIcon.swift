import SwiftUI

/// A rounded square in the brand colour with a white letter. The corner radius is a quarter of the size (5 pt at 20 pt).
struct LocalBrandIcon: View {
    let letter: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color)
            .overlay {
                Text(letter)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
    }
}
