import AppKit
import Observation
import UserNotifications
import CLIProxyBarCore

@MainActor
@Observable
final class QuotaResetAlerts: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var issue: String?
    @ObservationIgnored private let center: UNUserNotificationCenter?
    @ObservationIgnored private let confetti = ConfettiPresenter()
    @ObservationIgnored private var requestingPermission = false

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
    }

    var statusText: String {
        if let issue { return issue }
        switch authorizationStatus {
        case .denied: return "Notifications are blocked in macOS notification settings. Confetti can still work independently."
        case .authorized, .provisional: return "Notifications are allowed by macOS. Focus and system settings can silence them."
        default: return "macOS asks for notification permission when you enable an alert."
        }
    }

    func updateAuthorization(requestIfNeeded: Bool = false) async {
        guard center != nil else { return }
        authorizationStatus = await currentAuthorizationStatus()
        guard requestIfNeeded, authorizationStatus == .notDetermined, !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        do {
            try await requestNotificationPermission()
            authorizationStatus = await currentAuthorizationStatus()
            issue = nil
        } catch { issue = "macOS could not enable reset notifications. Try again in Settings." }
    }

    private func requestNotificationPermission() async throws {
        guard let center else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            center.requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        guard let center else { return .notDetermined }
        // Older SDKs do not mark UNNotificationSettings as Sendable. Extract
        // the scalar in its callback instead of moving the object across actors.
        let rawValue: Int = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
        return UNAuthorizationStatus(rawValue: rawValue) ?? .notDetermined
    }

    private func enqueueNotification(_ request: UNNotificationRequest) async throws {
        guard let center else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            center.add(request) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func previewConfetti() {
        if !confetti.show() { issue = "Confetti is paused while macOS Reduce Motion is enabled." }
        else { issue = nil }
    }

    func deliver(_ events: [QuotaResetEvent], preferences: DisplayPreferences) async {
        if preferences.celebratesLongResets, events.contains(where: { $0.kind == .long }) {
            confetti.show()
        }
        guard events.contains(where: { $0.kind == .short ? preferences.notifiesShortResets : preferences.notifiesLongResets }),
              center != nil else { return }
        await updateAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        let selected = events.filter { $0.kind == .short ? preferences.notifiesShortResets : preferences.notifiesLongResets }
        // Weekly model limits often reset together. Send one banner per account.
        for group in Dictionary(grouping: selected, by: \.accountID).values {
            guard let first = group.first else { continue }
            let provider = QuotaProvider(rawValue: first.provider)?.displayName ?? "Provider"
            let content = UNMutableNotificationContent()
            content.title = provider + " quota reset"
            content.subtitle = first.accountName
            content.body = group.map(\.windowName).sorted().joined(separator: ", ")
                + (group.count == 1 ? " allowance is available again." : " allowances are available again.")
            content.sound = .default
            content.threadIdentifier = "quota-reset-" + first.accountID
            let identifier = ProxyUsageHistory.digest(group.map(\.identifier).sorted().joined(separator: "\n"))
            do {
                try await enqueueNotification(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                issue = nil
            } catch { issue = "A reset notification could not be delivered. Check macOS notification settings." }
        }
    }

    func stop() { confetti.stop() }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
