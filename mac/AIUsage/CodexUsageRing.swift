import AppKit
import ApplicationServices
import SwiftUI

/// Draws one floating control above the built-in Usage ring while Codex is active.
@MainActor
final class CodexUsageRingController {
    private let panel = CodexRingPanel(
        contentRect: CGRect(origin: .zero, size: CodexUsageRingPlacement.size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    private let popover: UsagePopoverController
    private var tracker: QuotaOverlayTracker?
    private var defaults: NSKeyValueObservation?

    init(model: UsageViewModel, openMainWindow: @escaping () -> Void) {
        popover = UsagePopoverController(model: model, openMainWindow: openMainWindow, desktop: true)
        let visibility = QuotaOverlayVisibility()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        let ring = QuotaOverlayHostingView(rootView: QuotaOverlayButton(model: model, visibility: visibility, layout: .sidebar) { [weak self] in
            guard let self, let anchor = panel.contentView else { return }
            popover.toggle(relativeTo: anchor, edge: .maxX, activateApp: false)
        })
        ring.sizingOptions = []
        panel.contentView = ring
        tracker = QuotaOverlayTracker(panel: panel, visibility: visibility, bundleID: "com.openai.codex",
                                      isEnabled: { UserDefaults.standard.showCodexUsageRing },
                                      locate: CodexUsageAnchor.locate, followsWindowMovement: true) { [weak popover] in
            popover?.close(immediately: true)
        }
        defaults = UserDefaults.standard.observe(\.showCodexUsageRing, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.tracker?.contextChanged() }
        }
    }
}

private final class CodexRingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Reads geometry from the bottom of the left rail. The account button anchors the compact layout
/// even on builds that expose the usage icon without an accessibility label.
private enum CodexUsageAnchor {
    private static let buttons = [kAXButtonRole, kAXMenuButtonRole, kAXPopUpButtonRole,
                                  kAXCheckBoxRole, "AXToggleButton"]
    private static let blockers = buttons + [
        kAXMenuRole, kAXMenuItemRole, kAXTextFieldRole, kAXTextAreaRole, "AXLink",
        "AXPopover", "AXSheet", "AXDialog", "AXTooltip"
    ]

    static func locate(pid: pid_t) -> QuotaOverlayLocation? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        let focused: AXUIElement? = read(kAXFocusedWindowAttribute, app)
        let focusedSubrole: String? = focused.flatMap { read(kAXSubroleAttribute, $0) }
        let main: AXUIElement? = read(kAXMainWindowAttribute, app)
        let host = (focusedSubrole == nil || focusedSubrole == kAXStandardWindowSubrole ? focused : nil) ?? main
        guard let window = host,
              let bounds = frame(window),
              read(kAXMinimizedAttribute, window) as Bool? != true else { return nil }

        let rail = CGRect(x: bounds.minX - 1, y: bounds.minY, width: 82, height: bounds.height)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.18
        var nodes = [window]
        if let focusedItem: AXUIElement = read(kAXFocusedUIElementAttribute, app),
           let role: String = read(kAXRoleAttribute, focusedItem), blockers.contains(role) {
            nodes.append(focusedItem)
        }
        var index = 0
        var profile: CGRect?
        var usage: CGRect?
        var route: URL?
        var obstacles: [CGRect] = []
        let otherWindows: [AXUIElement] = read(kAXWindowsAttribute, app) ?? []
        for neighbor in otherWindows where !CFEqual(neighbor, window) {
            guard read(kAXMinimizedAttribute, neighbor) as Bool? != true,
                  read("AXHidden", neighbor) as Bool? != true,
                  let geometry = frame(neighbor), !geometry.isEmpty, geometry.intersects(rail) else { continue }
            // A backed-out dialog may be reported as a window. A regular background window is not an obstruction.
            let subrole: String? = read(kAXSubroleAttribute, neighbor)
            if subrole == kAXDialogSubrole || subrole == kAXFloatingWindowSubrole
                || focused.map({ CFEqual($0, neighbor) }) == true { obstacles.append(geometry) }
        }
        while index < nodes.count, ProcessInfo.processInfo.systemUptime < deadline {
            let node = nodes[index]
            index += 1
            if let geometry = frame(node), !geometry.isEmpty {
                guard geometry.intersects(rail) else { continue }
                let role: String = read(kAXRoleAttribute, node) ?? ""
                if route == nil, geometry.width >= bounds.width / 2, role == "AXWebArea" {
                    route = read(kAXURLAttribute, node)
                }
                if blockers.contains(role), read("AXHidden", node) as Bool? != true {
                    obstacles.append(geometry)
                }
                if geometry.width <= 58, geometry.height <= 54, bounds.contains(geometry),
                   buttons.contains(role), read("AXHidden", node) as Bool? != true {
                    let fromBottom = bounds.maxY - geometry.midY
                    if usage == nil, fromBottom >= 39, fromBottom <= 130, isUsage(node) {
                        usage = geometry
                    }
                    if fromBottom < 42, geometry.midX <= bounds.minX + 43,
                       profile == nil || fromBottom < bounds.maxY - profile!.midY {
                        profile = geometry
                    }
                }
            }
            guard nodes.count < 220 else { continue }
            var children: CFArray?
            if AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0, 24, &children) == .success,
               let children = children as? [AXUIElement] {
                nodes.append(contentsOf: children.prefix(220 - nodes.count))
            }
        }
        guard usage != nil || profile != nil,
              let ring = CodexUsageRingPlacement.frame(in: bounds, usage: usage, profile: profile,
                                                       avoiding: obstacles) else { return nil }
        let title: String? = read(kAXTitleAttribute, window)
        return QuotaOverlayLocation(window: window, frame: ring, surface: route?.absoluteString ?? title ?? "",
                                    placementLabel: "codexUsage")
    }

    private static func isUsage(_ element: AXUIElement) -> Bool {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute, "AXDOMIdentifier"].contains { key in
            guard let label: String = read(key, element) else { return false }
            let name = label.lowercased().replacingOccurrences(of: "-", with: " ")
            return name.contains("usage") || name.contains("rate limit") || name.contains("การใช้งาน")
        }
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let point: AXValue = read(kAXPositionAttribute, element),
              let size: AXValue = read(kAXSizeAttribute, element),
              CFGetTypeID(point) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(point, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private static func read<T>(_ key: String, _ element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
