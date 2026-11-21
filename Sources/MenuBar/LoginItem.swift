import Foundation
import Observation
import ServiceManagement

/// Reads the state from macOS each time, because people can also change it in
/// System Settings → General → Login Items.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var issue: String?

    init() { refresh() }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    var statusText: String {
        if let issue { return issue }
        if status == .requiresApproval {
            return "Allow CLIProxyBar in System Settings → General → Login Items."
        }
        return "CLIProxyBar opens in the menu bar when you log in."
    }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            issue = nil
        } catch {
            issue = "macOS did not change the login item: \(error.localizedDescription)"
        }
        refresh()
    }
}
