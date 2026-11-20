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

        // The Settings window: ⌘, and the gear in the app window open it.
        Settings {
            AppSettingsView(model: appDelegate.model, openAtLogin: appDelegate.openAtLogin)
        }
    }
}

/// Owns the one usage model and the menu bar item for the app's lifetime, so the window and the item share a model.
/// Closing the window keeps the app running.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageViewModel()
    /// The "Open at login" switch of the Settings window. It is the system's login item, not a settings.json key.
    let openAtLogin = OpenAtLoginModel(service: MainAppLoginItem())

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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentView(
            state: model.state,
            modelMixActions: ModelMixActions(
                setPercent: { model.setModelMixPercent($0, $1, to: $2) },
                moveOnto: { model.moveModelMix($0, $1, onto: $2) },
                step: { model.stepModelMix($0, $1, by: $2) },
                reset: { model.resetModelMix($0) },
                commitPercent: { model.commitModelMixPercent($0, $1) }
            ),
            onRefresh: { model.refresh() },
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            },
            onOpenLogs: { AppLinks.openLogsFolder() }
        )
        .environment(\.uiLanguage, model.uiLanguage)
        .onAppear {
            let openAction = openWindow
            register { openAction(id: AppWindowID.main) }
        }
    }
}
