import AppKit
import SwiftUI

@main
struct AIUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Quota Battery", id: AppWindowID.main) {
            MainWindowHost(model: appDelegate.model) { open in
                appDelegate.openMainWindowAction = open
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 530, height: 705)
    }
}

/// Owns the one usage model and the menu bar item for the app's lifetime, so the window and the item share a model.
/// Closing the window keeps the app running.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageViewModel()

    /// Opens the app window. The window sets it each time it appears, so it still works after the window was closed.
    var openMainWindowAction: (() -> Void)?

    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(model: model) { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Brings the app window forward. When the window was closed, it is opened again.
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let openMainWindowAction {
            openMainWindowAction()
        } else {
            NSApp.windows
                .first { $0.identifier?.rawValue.contains(AppWindowID.main) == true }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

enum AppWindowID {
    static let main = "main"
}

/// The content of the app window. When it appears, it hands its open action to the app delegate.
private struct MainWindowHost: View {
    @ObservedObject var model: UsageViewModel
    let register: (@escaping () -> Void) -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(
            state: model.state,
            accounts: model.accountsPanel,
            accountActions: AccountActions(
                rescan: { model.refresh() },
                add: { model.addAccount(provider: $0) },
                rename: { model.renameAccount($0, to: $1) },
                setEnabled: { model.setAccountEnabled($0, $1) },
                move: { model.moveAccount($0, onto: $1) },
                setSort: { model.setAccountSort($0) },
                setDirectMode: { model.setDirectMode($0, enabled: $1) }
            ),
            languageChoice: model.languageChoice,
            onSetLanguage: { model.setLanguage($0) },
            onRefresh: { model.refresh() },
            onOpenLogs: { AppLinks.openLogsFolder() }
        )
        .environment(\.uiLanguage, model.uiLanguage)
        .onAppear {
            let openAction = openWindow
            register { openAction(id: AppWindowID.main) }
        }
    }
}
