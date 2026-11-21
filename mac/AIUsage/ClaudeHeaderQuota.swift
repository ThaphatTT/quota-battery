import Foundation

enum ClaudeHeaderQuota {
    static let size = CGSize(width: 68, height: 36)
    static let railGap: CGFloat = 5

    static func frame(beside rail: CGRect) -> CGRect {
        CGRect(x: rail.minX - size.width - railGap, y: rail.midY - size.height / 2,
               width: size.width, height: size.height)
    }

    static func newSessionFrame(in window: CGRect, avoiding controls: [CGRect]) -> CGRect? {
        let ring = CGRect(x: window.maxX - 12 - size.width, y: window.minY + 6,
                          width: size.width, height: size.height)
        return clearingControls(from: ring, in: window, avoiding: controls)
    }

    static func clearingControls(from anchor: CGRect, in window: CGRect, avoiding controls: [CGRect]) -> CGRect? {
        var ring = anchor
        for control in controls.sorted(by: { $0.maxX > $1.maxX }) where ring.intersects(control) {
            ring.origin.x = control.minX - railGap - size.width
        }
        guard ring.maxX >= anchor.maxX - 98, window.contains(ring) else { return nil }
        return ring
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
