import SwiftUI

// MARK: - First appearance of a container

/// Fades an item in, and slides it up 8 pt in the `slide` style, once `shown` turns true. Items are staggered by `index`.
/// With `none`, the change is immediate, so a later appearance draws at once.
struct FirstOpenReveal: ViewModifier {
    let shown: Bool
    let style: IntroStyle
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || style != .slide ? 0 : 8)
            .animation(
                style == .none ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.06),
                value: shown
            )
    }
}

// MARK: - Skeleton

/// A grey rounded placeholder in the shape of a line, a square or a bar.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.primary.opacity(0.10))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// A soft band that sweeps left to right over the skeleton blocks. It runs only while `active` (see `SkeletonShimmer`).
/// The loop is cancelled when the skeleton leaves the screen, which is when the content replaces it.
struct SkeletonShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase = 0.0

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.14), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.5)
                        .offset(x: -proxy.size.width * 0.5 + phase * proxy.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .task {
                guard active else { return }
                let start = Date()
                await MotionLoop.run(interval: .milliseconds(33)) {
                    let elapsed = Date().timeIntervalSince(start)
                    phase = elapsed.truncatingRemainder(dividingBy: SkeletonShimmer.period) / SkeletonShimmer.period
                    return true
                }
            }
    }
}

/// A skeleton of some content. It is one element for VoiceOver, read as "กำลังโหลด / Loading", not once per block.
struct SkeletonLoadingView<Content: View>: View {
    let label: String
    let motion: MotionLevel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .modifier(SkeletonShimmerModifier(active: SkeletonShimmer.isRunning(loading: true, motion: motion)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// A skeleton account card: the icon square and the name line, then two limit lines (a label and a bar).
struct SkeletonAccountCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SkeletonBlock(width: 24, height: 24, radius: 6)
                SkeletonBlock(width: 140, height: 12)
                Spacer(minLength: 0)
            }
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 8) {
                    SkeletonBlock(width: 84, height: 10)
                    SkeletonBlock(height: 6, radius: 3)
                    SkeletonBlock(width: 40, height: 10)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

/// A skeleton row of the popover: the brand square, the name and a line, and the gauge.
struct SkeletonPopoverRow: View {
    var body: some View {
        HStack(spacing: 9) {
            SkeletonBlock(width: 28, height: 28, radius: 7)
            VStack(alignment: .leading, spacing: 5) {
                SkeletonBlock(width: 120, height: 11)
                SkeletonBlock(width: 180, height: 8)
            }
            Spacer(minLength: 6)
            SkeletonBlock(width: 40, height: 12)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

/// A skeleton row of the Accounts list: the handle, the brand square, the name and the source, and the switch.
struct SkeletonAccountRow: View {
    var body: some View {
        HStack(spacing: 10) {
            SkeletonBlock(width: 8, height: 14)
            SkeletonBlock(width: 24, height: 24, radius: 6)
            VStack(alignment: .leading, spacing: 5) {
                SkeletonBlock(width: 130, height: 11)
                SkeletonBlock(width: 90, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SkeletonBlock(width: 34, height: 18, radius: 9)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

/// A skeleton of the Model mix tab: the colour bar and three model rows.
struct SkeletonModelMix: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(height: 6, radius: 3)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 8) {
                    SkeletonBlock(width: 90, height: 10)
                    SkeletonBlock(height: 6, radius: 3)
                    SkeletonBlock(width: 36, height: 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Typing, rolling numbers, slot icon

/// A label that types in letter by letter (45 ms each) the first time it appears, when `key` is set and the motion is live.
/// Otherwise it is the plain text. The row sets the VoiceOver label, so the typing is not read letter by letter.
struct TypedText: View {
    let text: String
    var key: String?
    @Environment(\.motionLevel) private var motion
    @State private var visible: Int?

    var body: some View {
        if motion == .live, key != nil {
            Text(visible.map { String(text.prefix($0)) } ?? text)
                .task(id: key) {
                    guard let key, FirstOpenTracker.shared.claim("type." + key) else { return }
                    let start = Date()
                    visible = 0
                    let total = text.count
                    await MotionLoop.run {
                        let count = TypingPlan.visibleCount(total: total, elapsed: Date().timeIntervalSince(start))
                        visible = count
                        return count < total
                    }
                    visible = nil
                }
        } else {
            Text(text)
        }
    }
}

/// A number that counts from its shown value to `number` over 0.6 s. The first time it shows, it counts from 0. Later
/// changes count from the value on screen. Still motion (or no key) draws `text` at once.
struct RollingValue: View {
    /// The number shown, or nil when there is none (then `text` is drawn).
    let number: Double?
    /// The text drawn at rest, or with still motion. It must be `format(number)`.
    let text: String
    let format: (Double) -> String
    var key: String?
    @Environment(\.motionLevel) private var motion
    @State private var shown: Double?

    var body: some View {
        if motion == .live, key != nil, let number {
            Text(format(shown ?? number))
                .task(id: number) {
                    guard let key else { return }
                    let from: Double
                    if FirstOpenTracker.shared.claim("roll." + key) {
                        from = 0
                    } else {
                        from = shown ?? number
                    }
                    guard from != number else { return }
                    let start = Date()
                    await MotionLoop.run {
                        let elapsed = Date().timeIntervalSince(start)
                        shown = RollingPlan.value(from: from, to: number, elapsed: elapsed)
                        return elapsed < RollingPlan.duration
                    }
                    shown = number
                }
        } else {
            Text(text)
        }
    }
}

/// The brand letter square. On its first appearance (with a `key`, and live motion) the letters roll and land on the
/// brand letter. Otherwise it is `LocalBrandIcon`.
struct SlotBrandIcon: View {
    let letter: String
    let color: Color
    var size: CGFloat = 28
    var key: String?
    @Environment(\.motionLevel) private var motion
    @State private var position: Double?

    var body: some View {
        if motion == .live, key != nil {
            SlotStrip(letter: letter, color: color, size: size, key: key, position: $position)
        } else {
            LocalBrandIcon(letter: letter, color: color, size: size)
        }
    }
}

private struct SlotStrip: View {
    let letter: String
    let color: Color
    let size: CGFloat
    let key: String?
    @Binding var position: Double?

    var body: some View {
        let strip = SlotPlan.strip(letter: letter)
        let landed = Double(strip.count - 2)
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color)
            .overlay {
                VStack(spacing: 0) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { _, glyph in
                        Text(glyph)
                            .font(.system(size: size * 0.46, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: size, height: size)
                    }
                }
                .offset(y: -(position ?? landed) * size)
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .frame(width: size, height: size)
            .task(id: key) {
                guard let key, FirstOpenTracker.shared.claim("slot." + key) else { return }
                let start = Date()
                position = 0
                let count = strip.count
                await MotionLoop.run {
                    let progress = Date().timeIntervalSince(start) / SlotPlan.duration
                    position = SlotPlan.position(progress: progress, count: count)
                    return progress < 1
                }
                position = nil
            }
    }
}

// MARK: - Still-or-live helpers

// These are functions, not views: a still draw (a snapshot, Reduce Motion) gets the plain Text or icon with no extra
// view layer, so the loaded window costs what it did before the first-open motion existed.

/// `TypedText` when the label is to type in on its first showing, otherwise plain text.
@ViewBuilder
func typedText(_ text: String, key: String?, motion: MotionLevel) -> some View {
    if motion == .live, key != nil {
        TypedText(text: text, key: key)
    } else {
        Text(text)
    }
}

/// `RollingValue` when the number counts up on its first showing, otherwise the plain text.
@ViewBuilder
func rollingText(
    number: Double?, text: String, format: @escaping (Double) -> String, key: String?, motion: MotionLevel
) -> some View {
    if motion == .live, key != nil, number != nil {
        RollingValue(number: number, text: text, format: format, key: key)
    } else {
        Text(text)
    }
}

/// `SlotBrandIcon` when the brand letter rolls in on its first showing, otherwise the plain icon.
@ViewBuilder
func slotBrand(_ letter: String, color: Color, size: CGFloat, key: String?, motion: MotionLevel) -> some View {
    if motion == .live, key != nil {
        SlotBrandIcon(letter: letter, color: color, size: size, key: key)
    } else {
        LocalBrandIcon(letter: letter, color: color, size: size)
    }
}
