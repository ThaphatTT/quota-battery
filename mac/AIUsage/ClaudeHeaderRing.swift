import AppKit
import ApplicationServices
import SwiftUI

/// Draws the overlay beside Session Rail or in the free header of a new session.
@MainActor
final class ClaudeHeaderRing {
    private let panel = RingPanel(
        contentRect: CGRect(origin: .zero, size: ClaudeHeaderQuota.size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    private let usagePopover: UsagePopoverController
    private var tracker: QuotaOverlayTracker?
    private var defaultsObservation: NSKeyValueObservation?

    init(model: UsageViewModel, openMainWindow: @escaping () -> Void) {
        usagePopover = UsagePopoverController(model: model, openMainWindow: openMainWindow, desktop: true)
        let visibility = QuotaOverlayVisibility()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false

        let button = QuotaOverlayHostingView(rootView: QuotaOverlayButton(model: model, visibility: visibility, layout: .header) { [weak self] in
            guard let self, let button = panel.contentView else { return }
            usagePopover.toggle(relativeTo: button, edge: .minY, activateApp: false)
        })
        button.sizingOptions = []
        panel.contentView = button

        tracker = QuotaOverlayTracker(panel: panel, visibility: visibility, bundleID: "com.anthropic.claudefordesktop",
                                      isEnabled: { UserDefaults.standard.showClaudeHeaderRing },
                                      locate: ClaudeSessionToolbar().locate, followsWindowMovement: true) { [weak usagePopover] in
            usagePopover?.close(immediately: true)
        }
        defaultsObservation = UserDefaults.standard.observe(\.showClaudeHeaderRing, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.tracker?.contextChanged() }
        }
    }
}

final class QuotaOverlayHostingView: NSHostingView<QuotaOverlayButton> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class RingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // The anchor is checked against the screen before display. The normal visible-frame
    // constraint would shift the panel down when its target touches the menu bar area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class ClaudeSessionToolbar {
    // The tracker serializes probes. Keep offsets for each Claude window across page changes.
    private var layout = ClaudeHeaderQuota.Layout()
    private var processID: pid_t?

    private static let buttonRoles = [kAXButtonRole, kAXCheckBoxRole, kAXMenuButtonRole, "AXToggle", "AXToggleButton"]

    private static let interactiveRoles = buttonRoles + [
        kAXPopUpButtonRole, kAXTextFieldRole, kAXTextAreaRole, "AXLink",
        kAXMenuRole, kAXMenuItemRole, "AXPopover", "AXSheet", "AXDialog", "AXTooltip"
    ]
    private static let newSessionNames = ["New session", "New Code Session", "New Claude Code Session", "Start a new session",
                                          "New chat", "Start a new chat", "What would you like to work on?"]

    /// AX positions use the top-left of the primary screen. Keep everything in that space until display.
    func locate(pid: pid_t) -> QuotaOverlayLocation? {
        if processID != pid {
            processID = pid
            layout = ClaudeHeaderQuota.Layout()
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let focusedWindow: AXUIElement? = Self.attribute(kAXFocusedWindowAttribute, in: app)
        let mainWindow: AXUIElement? = Self.attribute(kAXMainWindowAttribute, in: app)
        guard let window = focusedWindow ?? mainWindow,
              Self.attribute(kAXMinimizedAttribute, in: window) as Bool? != true,
              let windowFrame = Self.frame(of: window) else { return nil }
        let nodes = Self.descendants(of: window, limit: 140)
        let webArea = nodes.first { node in
            guard Self.role(of: node) == "AXWebArea", let bounds = Self.frame(of: node) else { return false }
            return bounds.width >= windowFrame.width / 2 && bounds.intersects(windowFrame)
        }
        let route: URL? = webArea.flatMap { Self.attribute(kAXURLAttribute, in: $0) }
        let title: String? = Self.attribute(kAXTitleAttribute, in: window)
        let surface = route?.absoluteString ?? title ?? ""
        let sessionToolbar = nodes.first {
            Self.role(of: $0) == kAXToolbarRole && Self.hasName("Session tools", element: $0)
        }
        let toolbarNodes = sessionToolbar.map { Self.descendants(of: $0, limit: 48) } ?? []
        var visibleNodes = nodes + toolbarNodes
        if let focusedItem: AXUIElement = Self.attribute(kAXFocusedUIElementAttribute, in: app) {
            visibleNodes.append(focusedItem)
        }
        let controls = Self.interactiveFrames(in: visibleNodes, nearTopOf: windowFrame)
        let toolbarFrame = sessionToolbar.flatMap { Self.frame(of: $0) }
        let rail = Self.railFrame(in: toolbarNodes, window: windowFrame, toolbar: toolbarFrame)
            ?? Self.railFrame(in: nodes, window: windowFrame)
        let isNew = rail == nil && (route.map(ClaudeHeaderQuota.isNewSessionURL) == true
            || nodes.contains { Self.isNewSessionContent($0, in: windowFrame) })
        guard let position = layout.placement(windowID: CFHash(window), window: windowFrame, rail: rail,
                                              isNewSession: isNew, controls: controls) else { return nil }
        return QuotaOverlayLocation(window: window, frame: position.frame,
                                    surface: "\(position.anchor.rawValue):\(surface)",
                                    placementLabel: position.anchor.rawValue)
    }

    private static func isNewSessionContent(_ node: AXUIElement, in window: CGRect) -> Bool {
        let nodeRole = role(of: node)
        if nodeRole == "AXWebArea" {
            let url: URL? = attribute(kAXURLAttribute, in: node)
            return url.map(ClaudeHeaderQuota.isNewSessionURL) == true
                && frame(of: node).map { window.intersects($0) && $0.width >= window.width / 2 } == true
        }
        let contentRoles = [kAXGroupRole, kAXStaticTextRole, kAXTextAreaRole, kAXTextFieldRole, "AXHeading"]
        return contentRoles.contains(nodeRole) && hasName(in: newSessionNames, element: node)
            && frame(of: node).map { window.contains($0) && $0.midX >= window.minX + window.width * 0.35 } == true
    }

    private static func railFrame(in nodes: [AXUIElement], window: CGRect, toolbar: CGRect? = nil) -> CGRect? {
        let candidates = nodes.compactMap { node -> CGRect? in
            guard buttonRoles.contains(role(of: node)),
                  attribute("AXHidden", in: node) as Bool? != true,
                  [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute, "AXDOMIdentifier"]
                  .contains(where: { key in
                      let value: String? = attribute(key, in: node)
                      return value.map(ClaudeHeaderQuota.isSessionRailLabel) == true
                  }) else { return nil }
            return frame(of: node)
        }
        return ClaudeHeaderQuota.rail(in: candidates, window: window, toolbar: toolbar)
    }

    private static func interactiveFrames(in nodes: [AXUIElement], nearTopOf window: CGRect) -> [CGRect] {
        let top = CGRect(x: window.minX, y: window.minY, width: window.width, height: 140)
        return nodes.compactMap {
            guard interactiveRoles.contains(role(of: $0)), let frame = frame(of: $0),
                  attribute("AXHidden", in: $0) as Bool? != true,
                  frame.intersects(top), !frame.isEmpty else { return nil }
            return frame
        }
    }

    private static func descendants(of root: AXUIElement, limit: Int) -> [AXUIElement] {
        var elements: [AXUIElement] = [root]
        var index = 0
        while index < elements.count && elements.count < limit {
            let element = elements[index]
            index += 1
            if role(of: element) == kAXGroupRole,
               ["Sidebar", "Chat messages", "Session details"].contains(where: { hasName($0, element: element) }) {
                continue
            }
            var children: CFArray?
            if AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, 32, &children) == .success,
               let children = children as? [AXUIElement] {
                elements.append(contentsOf: children.prefix(limit - elements.count))
            }
        }
        return elements
    }

    private static func role(of element: AXUIElement) -> String {
        attribute(kAXRoleAttribute, in: element) ?? ""
    }

    private static func hasName(_ name: String, element: AXUIElement) -> Bool {
        hasName(in: [name], element: element)
    }

    private static func hasName(in names: [String], element: AXUIElement) -> Bool {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXPlaceholderValue"].contains { key in
            let value: String? = attribute(key, in: element)
            return names.contains { value?.caseInsensitiveCompare($0) == .orderedSame }
        }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(kAXPositionAttribute, in: element),
              let size: AXValue = attribute(kAXSizeAttribute, in: element),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private static func attribute<T>(_ key: String, in element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
