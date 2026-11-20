import Foundation

/// What the system says about the app's login item.
enum LoginItemStatus: Equatable {
    case enabled
    case notRegistered
    /// Registered, but the user has not allowed it yet in System Settings > Login Items.
    case requiresApproval
    case notFound
}

/// The app's login item. The app uses `SMAppService.mainApp` (see `MainAppLoginItem`); a test passes a fake, so no test
/// registers the app for login.
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// The "Open at login" switch. It shows the status the system reports. After every change the status is read again, so
/// the switch never shows a value the system did not confirm. It is not saved to settings.json.
@MainActor
final class OpenAtLoginModel: ObservableObject {
    @Published private(set) var status: LoginItemStatus
    /// True after a change that the system refused. The next change clears it.
    @Published private(set) var failed = false
    private let service: LoginItemService

    init(service: LoginItemService) {
        self.service = service
        status = service.status
    }

    /// On when the item is registered. An item that waits for approval is on too: it starts once the user allows it.
    var isOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// Reads the status again. The Settings window calls it when it appears, so a change made in System Settings shows.
    func refresh() {
        status = service.status
    }

    /// Registers or unregisters the item, then reads the status again.
    func setEnabled(_ on: Bool) {
        failed = false
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            failed = true
        }
        status = service.status
    }
}
