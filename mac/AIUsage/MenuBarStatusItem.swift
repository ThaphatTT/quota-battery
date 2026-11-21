import AppKit
import SwiftUI

/// The menu bar label: a small ring and the number of what is left. At more than 20% left it is a template, so the
/// system colours it (white on a dark bar, black on a light one). At 6 to 20% left it is yellow, and at 5% or less red,
/// and those are not templates, so the colour survives the menu bar. The yellow and red follow the appearance:
/// `#FFD60A` and `#FF5F57` on a dark bar, `#B58900` and `#D93025` on a light one.
struct MenuBarStatusGlyph: View {
    /// The used percent of the account and limit with the least left, or nil when there is no data.
    let percent: Double?
    let tier: UsageTier
    var pulse: Double = 1
    /// True when the menu bar is dark. Picks the dark or the light yellow and red.
    var dark: Bool = true
    /// Set only by the snapshot driver, to preview on a dark bar. Nil uses black for the template, or the tier colour.
    var tint: Color? = nil

    var body: some View {
        let color = tint ?? tier.hex(dark: dark).map { Color(hex: $0) } ?? Color.black
        HStack(spacing: 4) {
            LocalUsageRing(
                progress: percent.map { UsageFormat.remainingFraction($0) },
                tint: color,
                size: 12,
                lineWidth: 2
            )
            Text(AppUsageInsights.statusTitle(percent))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 2)
        .fixedSize()
        .frame(height: 16)
        .opacity(pulse)
    }
}

/// Owns the menu bar image. The number glides from the old value to the new one (about 0.14 s to settle),
/// and a crossing up to 80% used pulses once. The model passes the USED percent in; the glyph shows what is left.
@MainActor
final class MenuBarStatusItem: ObservableObject {
    @Published private(set) var image: NSImage

    private var target: Double?
    private var shown: Double?
    private var pulseStart: Date?
    private var timer: Timer?
    /// The glide of the number and the ring: a liquid spring (fraction of the used percent). Nil when nothing moves.
    private var spring: LiquidSpring?
    /// True once the first value has been shown. The first value grows the ring from empty, once per app session.
    private var hasGrown = false

    /// The first value grows in after this delay, so the menu bar has settled when it starts.
    private static let growDelay: TimeInterval = 0.15
    private static let pulseLength: TimeInterval = 0.9
    private static let frameTime: TimeInterval = 1.0 / 60.0
    /// Posted by the system when the light or dark appearance changes. The yellow and red of the icon change with it.
    private static let appearanceNotification = Notification.Name("AppleInterfaceThemeChangedNotification")

    private var appearanceObserver: NSObjectProtocol?

    init() {
        image = MenuBarStatusItem.render(percent: nil, tier: .plenty, pulse: 1, dark: MenuBarStatusItem.isDarkMenuBar)
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.appearanceNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.redraw()
            }
        }
    }

    /// True when the app's appearance is dark. The menu bar follows the system appearance.
    static var isDarkMenuBar: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Sets the used percent to show. Nil means there is no data.
    func set(percent: Double?) {
        // The same value, with nothing gliding or pulsing: the image already shows it, so nothing is drawn again.
        if percent == target, shown == target, timer == nil, pulseStart == nil { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if AppUsageInsights.crossedAlert(previous: target, current: percent), !reduced {
            pulseStart = Date()
        }
        target = percent
        spring = nil
        if percent == nil || reduced {
            shown = percent
        } else if !hasGrown {
            // The first value grows the ring in from empty, once per app session.
            hasGrown = true
            spring = LiquidSpring(position: 0, target: percent.map { $0 / 100 } ?? 0, startAt: Date().addingTimeInterval(Self.growDelay))
            shown = 0
        } else if let current = shown {
            // A value change: the ring and the number move on a liquid spring from the value on screen.
            spring = LiquidSpring(position: current / 100, target: (percent ?? 0) / 100)
        } else {
            shown = percent
        }
        redraw()
        if shown != target || pulseStart != nil || spring != nil {
            startTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.frameTime, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.step()
            }
        }
    }

    private func step() {
        if let spring, let goal = target {
            spring.advance(to: Date())
            if spring.isSettled {
                shown = goal
                self.spring = nil
            } else {
                shown = min(max(spring.position, 0), 1) * 100
            }
        } else {
            shown = target
        }
        redraw()
        if shown == target && pulseStart == nil {
            timer?.invalidate()
            timer = nil
        }
    }

    private func redraw() {
        var pulse = 1.0
        if let start = pulseStart {
            let progress = Date().timeIntervalSince(start) / Self.pulseLength
            if progress >= 1 {
                pulseStart = nil
            } else {
                pulse = 1 - 0.6 * sin(Double.pi * progress)
            }
        }
        // The colour follows the target, so it changes at once while the number glides.
        image = MenuBarStatusItem.render(
            percent: shown,
            tier: UsageFormat.tier(target),
            pulse: pulse,
            dark: Self.isDarkMenuBar
        )
    }

    /// Draws the glyph at 2x. A template image only at more than 20% left, so the system tints it.
    static func render(percent: Double?, tier: UsageTier, pulse: Double, dark: Bool) -> NSImage {
        let glyph = MenuBarStatusGlyph(percent: percent, tier: tier, pulse: pulse, dark: dark)
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else {
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let size = NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2)
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = tier == .plenty
        return image
    }
}
