import AppKit
import Combine
import SwiftUI

/// The menu bar item. AppKit draws it, so it can keep a stable autosave name: the position the user chooses is saved
/// under that name. It is created once, when the app launches, and is never removed or re-created. The "show icon"
/// switch in the app window only changes `isVisible`.
@MainActor
final class StatusItemController: NSObject {
    private let model: UsageViewModel
    private let openMainWindow: () -> Void
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var imageSubscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?
    /// Watches the "show icon" key only. See `UserDefaults.showMenuBarIcon`.
    private var visibilitySwitch: NSKeyValueObservation?
    /// The value of the switch that was handled last. Nil until the first look at launch.
    private var appliedVisibility: Bool?
    /// True while `isVisible` is being set. AppKit writes its own defaults then, which must not start the rule again.
    private var isApplyingVisibility = false
    /// When the popover last closed. A click on the icon closes the popover first, then arrives as a toggle,
    /// so a toggle right after a close is ignored.
    private var lastClosedAt: Date?

    private static let autosaveName = "AIUsageStatusItem"

    init(model: UsageViewModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // The order matters: the autosave name and the behaviour come before visibility, so that AppKit
        // stores the visibility under the autosave name and not under a generic key.
        statusItem.autosaveName = Self.autosaveName
        statusItem.behavior = []
        applyVisibility()

        popover.behavior = .transient
        popover.delegate = self

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

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        if let lastClosedAt, Date().timeIntervalSince(lastClosedAt) < 0.3 {
            return
        }
        guard let button = statusItem.button else { return }
        let content = makeContentController()
        popover.contentViewController = content
        let size = content.view.fittingSize
        if size.width > 0, size.height > 0 {
            popover.contentSize = size
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// A new hosting controller for each opening, so the rows fade in again every time the popover opens.
    private func makeContentController() -> NSViewController {
        let host = NSHostingController(
            rootView: MenuBarPopoverHost(
                model: model,
                onOpenApp: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.openMainWindow()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
        host.sizingOptions = [.preferredContentSize]
        return host
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        lastClosedAt = Date()
        // The closed popover's views would still follow the model, so they are let go until the next opening.
        popover.contentViewController = nil
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
