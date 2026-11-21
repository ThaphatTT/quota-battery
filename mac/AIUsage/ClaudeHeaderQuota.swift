import Foundation

enum ClaudeHeaderQuota {
    static let size = CGSize(width: 68, height: 36)
    static let railGap: CGFloat = 5

    struct Placement: Equatable {
        enum Anchor: String { case sessionRail, newSessionSlot }
        let frame: CGRect
        let anchor: Anchor
    }

    struct Layout {
        private struct RailSlot {
            let trailingInset: CGFloat
            let topToCenter: CGFloat
            let size: CGSize

            init(window: CGRect, rail: CGRect) {
                trailingInset = window.maxX - rail.maxX
                topToCenter = rail.midY - window.minY
                size = rail.size
            }

            func rail(in window: CGRect) -> CGRect {
                CGRect(x: window.maxX - trailingInset - size.width, y: window.minY + topToCenter - size.height / 2,
                       width: size.width, height: size.height)
            }
        }

        private var slots: [UInt: RailSlot] = [:]

        mutating func placement(windowID: UInt, window: CGRect, rail: CGRect?, isNewSession: Bool,
                                controls: [CGRect]) -> Placement? {
            let result: Placement
            if let rail {
                guard !rail.isEmpty, window.contains(rail) else { return nil }
                slots[windowID] = RailSlot(window: window, rail: rail)
                result = Placement(frame: ClaudeHeaderQuota.frame(beside: rail), anchor: .sessionRail)
            } else {
                guard isNewSession, window.width >= 380, window.height >= 240 else { return nil }
                // Reserve the native button's footprint even before Claude mounts the rail.
                let expectedRail = slots[windowID]?.rail(in: window)
                    ?? CGRect(x: window.maxX - 12 - 28, y: window.minY + 10, width: 28, height: 28)
                result = Placement(frame: ClaudeHeaderQuota.frame(beside: expectedRail), anchor: .newSessionSlot)
            }
            guard window.contains(result.frame),
                  !controls.contains(where: { !result.frame.intersection($0).isEmpty }) else { return nil }
            return result
        }
    }

    static func frame(beside rail: CGRect) -> CGRect {
        CGRect(x: rail.minX - size.width - railGap, y: rail.midY - size.height / 2,
               width: size.width, height: size.height)
    }

    static func isSessionRailLabel(_ label: String) -> Bool {
        let name = label.lowercased().split(whereSeparator: { !$0.isLetter }).joined(separator: " ")
        return [
            "session rail", "toggle session rail", "show session rail", "hide session rail",
            "open session rail", "close session rail", "session rail button", "session rail toggle",
            "session rail expanded", "session rail collapsed"
        ].contains(name)
    }

    static func rail(in candidates: [CGRect], window: CGRect, toolbar: CGRect? = nil) -> CGRect? {
        candidates.filter {
            !$0.isEmpty && window.contains($0) && $0.width <= 72 && $0.height <= 52
                && (toolbar?.contains(CGPoint(x: $0.midX, y: $0.midY)) ?? ($0.midX > window.midX))
                && $0.midY < window.minY + 120
        }.max { ($0.maxX, -$0.midY) < ($1.maxX, -$1.midY) }
    }

    static func isNewSessionURL(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch (url.scheme, url.host) {
        case ("https", "claude.ai"): return ["new", "code", "code/new"].contains(path)
        case ("claude", "claude.ai"): return ["new", "code/new"].contains(path)
        case ("claude", "code"): return path == "new"
        default: return false
        }
    }
}
