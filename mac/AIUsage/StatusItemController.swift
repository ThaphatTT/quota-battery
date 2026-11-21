import AppKit
import Combine
import SwiftUI

/// The menu bar item. AppKit draws it, so it can keep a stable autosave name: the position the user chooses is saved
/// under that name. It is created once, when the app launches, and is never removed or re-created. The "show icon"
/// switch in the app window only changes `isVisible`.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let usagePopover: UsagePopoverController
    private var imageSubscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?
    /// Watches the "show icon" key only. See `UserDefaults.showMenuBarIcon`.
    private var visibilitySwitch: NSKeyValueObservation?
    /// The value of the switch that was handled last. Nil until the first look at launch.
    private var appliedVisibility: Bool?
    /// True while `isVisible` is being set. AppKit writes its own defaults then, which must not start the rule again.
    private var isApplyingVisibility = false
    private static let autosaveName = "AIUsageStatusItem"

    init(model: UsageViewModel, openMainWindow: @escaping () -> Void) {
        usagePopover = UsagePopoverController(model: model, openMainWindow: openMainWindow)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // The order matters: the autosave name and the behaviour come before visibility, so that AppKit
        // stores the visibility under the autosave name and not under a generic key.
        statusItem.autosaveName = Self.autosaveName
        statusItem.behavior = []
        applyVisibility()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageOnly
            // Only the image changes. The item itself is never touched again.
            imageSubscription = model.statusItem.$image.sink { [weak button] image in
                button?.image = image
            }
            // The accessibility label follows the language. The value comes from the publisher, because a published
            // property changes after it has sent its value.
            languageSubscription = model.$languageChoice.sink { [weak button] choice in
                button?.setAccessibilityLabel(L10n.text(.usageTitle, UILanguage.current(for: choice)))
            }
        }

        // Only the "show icon" key is observed. The changes AppKit makes to its own defaults do not reach this.
        visibilitySwitch = UserDefaults.standard.observe(\.showMenuBarIcon, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyVisibility() }
        }
    }

    /// Follows the "show icon" switch. A missing value means on, the same default as the switch's @AppStorage.
    /// The rule is `MenuBarIconSwitchRule`: `isVisible` is set only when the switch changed, and never while it is being set.
    private func applyVisibility() {
        let wanted = UserDefaults.standard.object(forKey: AppSettingKey.showMenuBarIcon) as? Bool ?? true
        let step = MenuBarIconSwitchRule.step(
            wanted: wanted,
            lastApplied: appliedVisibility,
            isVisibleNow: statusItem.isVisible,
            isApplying: isApplyingVisibility
        )
        switch step {
        case .nothing:
            return
        case .rememberOnly:
            appliedVisibility = wanted
        case .setVisible(let value):
            appliedVisibility = value
            isApplyingVisibility = true
            defer { isApplyingVisibility = false }
            statusItem.isVisible = value
        }
    }

    @objc private func togglePopover(_ sender: NSButton) {
        usagePopover.toggle(relativeTo: sender, edge: .minY, activateApp: true)
    }
}

/// Hosts the same usage view from any AppKit button.
@MainActor
final class UsagePopoverController: NSObject, NSPopoverDelegate {
    private let model: UsageViewModel
    private let openMainWindow: () -> Void
    private let desktop: Bool
    private let popover = NSPopover()
    private let presentation = DesktopPopoverPresentation()
    private weak var positioningView: NSView?
    private var dismissal: Task<Void, Never>?
    /// The macOS menu-bar popover can dismiss on the anchor's mouse-down before its mouse-up.
    private var lastClosedAt: Date?

    init(model: UsageViewModel, openMainWindow: @escaping () -> Void, desktop: Bool = false) {
        self.model = model
        self.openMainWindow = openMainWindow
        self.desktop = desktop
        super.init()
        popover.behavior = .transient
        popover.animates = !desktop
        popover.delegate = self
    }

    func close(immediately: Bool = false) {
        if immediately {
            dismissal?.cancel()
            dismissal = nil
            presentation.reset()
            guard popover.isShown else { return }
            let animates = popover.animates
            popover.animates = false
            popover.close()
            popover.animates = animates
        } else if desktop {
            if presentation.beginClosing() { finishAfterAnimation() }
        } else if popover.isShown {
            popover.performClose(nil)
        }
    }

    func toggle(relativeTo button: NSView, edge: NSRectEdge, activateApp: Bool) {
        if desktop {
            guard button.window?.isVisible == true else { return }
            switch presentation.toggle() {
            case .mount:
                show(relativeTo: button, edge: edge, activateApp: activateApp)
            case .dismiss:
                finishAfterAnimation()
            case .reverseDismissal:
                dismissal?.cancel()
                dismissal = nil
            }
            return
        }
        if popover.isShown {
            close()
            return
        }
        if let lastClosedAt, Date().timeIntervalSince(lastClosedAt) < 0.3 { return }
        show(relativeTo: button, edge: edge, activateApp: activateApp)
    }

    private func finishAfterAnimation() {
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(DesktopPopoverPresentation.duration)) } catch { return }
            guard !Task.isCancelled, let self, self.presentation.phase == .closing else { return }
            self.dismissal = nil
            self.presentation.reset()
            self.popover.close()
        }
    }

    private func show(relativeTo button: NSView, edge: NSRectEdge, activateApp: Bool) {
        let content = makeContentController()
        positioningView = button
        popover.contentViewController = content
        let size = content.view.fittingSize
        if size.width > 0, size.height > 0 {
            popover.contentSize = size
        }
        if activateApp { NSApp.activate(ignoringOtherApps: true) }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: edge)
        if desktop, !popover.isShown {
            presentation.reset()
            popover.contentViewController = nil
            positioningView = nil
        }
    }

    private func makeContentController() -> NSViewController {
        let openApp: () -> Void = { [weak self] in
            guard let self else { return }
            self.close(immediately: self.desktop)
            self.openMainWindow()
        }
        let quit: () -> Void = { NSApplication.shared.terminate(nil) }
        if desktop {
            let host = NSHostingController(rootView: DesktopQuotaDetails(model: model, presentation: presentation,
                                                                         onOpenApp: openApp, onQuit: quit))
            host.sizingOptions = [.preferredContentSize]
            return host
        }
        let host = NSHostingController(rootView: MenuBarPopoverHost(model: model, onOpenApp: openApp, onQuit: quit))
        host.sizingOptions = [.preferredContentSize]
        return host
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard desktop, presentation.phase != .hidden else { return true }
        // The overlay's button owns its click. Outside dismissal and Escape still fade out.
        if let view = positioningView, let window = view.window {
            let mouse = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let release = NSApp.currentEvent?.type == .leftMouseUp && NSApp.currentEvent?.window === window
            if (NSEvent.pressedMouseButtons & 1 != 0 || release),
               view.bounds.contains(view.convert(mouse, from: nil)) { return false }
        }
        close()
        return false
    }

    func popoverDidShow(_ notification: Notification) {
        guard desktop, let content = popover.contentViewController else { return }
        DispatchQueue.main.async { [weak self, weak content] in
            guard let self, let content, self.popover.contentViewController === content else { return }
            self.presentation.didShow()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastClosedAt = Date()
        dismissal?.cancel()
        dismissal = nil
        presentation.reset()
        popover.contentViewController = nil
        positioningView = nil
    }
}

/// The popover's root view. It sets the language for everything in the popover, and it observes the model, so the
/// rows update while the popover is open.
struct MenuBarPopoverHost: View {
    @ObservedObject var model: UsageViewModel
    let onOpenApp: () -> Void
    let onQuit: () -> Void

    var body: some View {
        MenuBarPopoverView(
            state: model.state,
            onRefresh: { model.refresh() },
            onOpenApp: onOpenApp,
            onQuit: onQuit
        )
        .environment(\.uiLanguage, model.uiLanguage)
    }
}

/// The "show icon" switch as a key-value observable property. The name is the stored key, so KVO fires when the switch
/// writes it. A missing value means on, as in the switch's @AppStorage.
extension UserDefaults {
    @objc dynamic var showMenuBarIcon: Bool {
        object(forKey: AppSettingKey.showMenuBarIcon) as? Bool ?? true
    }
}
