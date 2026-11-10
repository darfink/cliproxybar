import AppKit
import SwiftUI
import CLIProxyBarCore

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let preferences: DisplayPreferences
    private let updater: AppUpdater
    private let resetAlerts: QuotaResetAlerts
    private let didRemoveAccount: (ProxyAccount, URL) -> Void
    private let onKeySaved: () -> Void
    private let navigation = SettingsNavigation()
    init(preferences: DisplayPreferences, updater: AppUpdater, resetAlerts: QuotaResetAlerts, onKeySaved: @escaping () -> Void, didRemoveAccount: @escaping (ProxyAccount, URL) -> Void) {
        self.didRemoveAccount = didRemoveAccount
        self.preferences = preferences
        self.updater = updater
        self.resetAlerts = resetAlerts
        self.onKeySaved = onKeySaved
    }

    func show(section: SettingsSection? = nil) {
        if let section { navigation.selection = section }
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "CLIProxyBar Settings"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: SettingsTabsView(preferences: preferences, updater: updater,
                resetAlerts: resetAlerts, onKeySaved: onKeySaved, didRemoveAccount: didRemoveAccount,
                navigation: navigation, close: { [weak panel] in panel?.close() }))
            panel.center()
            window = panel
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsSection: String, CaseIterable {
    case display = "Display"
    case accounts = "Accounts"
    case alertsHistory = "Alerts & History"
    case connection = "Connection"
}

@MainActor @Observable
final class SettingsNavigation {
    var selection: SettingsSection = .display
}

private struct SettingsTabsView: View {
    @Bindable var preferences: DisplayPreferences
    @Bindable var updater: AppUpdater
    let resetAlerts: QuotaResetAlerts
    let onKeySaved: () -> Void
    let didRemoveAccount: (ProxyAccount, URL) -> Void
    @Bindable var navigation: SettingsNavigation
    let close: () -> Void
    private var selection: SettingsSection { navigation.selection }

    var body: some View {
        SettingsLayout(selection: $navigation.selection) {
            // Keep panels mounted so tab changes preserve drafts and scroll positions.
            ZStack {
                pane(.display) { DisplaySettingsView(preferences: preferences) }
                pane(.accounts) {
                    AccountSettingsView(endpoint: preferences.endpoint, didRemove: didRemoveAccount,
                                        isActive: selection == .accounts)
                }
                pane(.alertsHistory) {
                    AlertsHistorySettingsView(preferences: preferences, resetAlerts: resetAlerts)
                }
                pane(.connection) {
                    ConnectionSettingsView(preferences: preferences, updater: updater, onKeySaved: onKeySaved)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } footer: {
            HStack {
                Text("CLIProxyBar · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func pane<Content: View>(_ section: SettingsSection, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selection == section ? 1 : 0)
            .allowsHitTesting(selection == section)
            .disabled(selection != section)
            .accessibilityHidden(selection != section)
    }
}

struct SettingsLayout<Content: View, Footer: View>: View {
    @Binding var selection: SettingsSection
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 8) {
            // TabView can move into macOS titlebar overflow; keep navigation in the content.
            Picker("Settings section", selection: $selection) {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.top, 4)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer.padding(.horizontal, 8)
        }
        .padding(12)
        .frame(width: 480, height: 660)
    }
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DisplaySettingsView: View {
    @Bindable var preferences: DisplayPreferences

    var body: some View {
        SettingsPage {
            Text("Quota display").font(.headline)
            Picker("Quota display", selection: $preferences.mode) {
                Text("Usage").tag(QuotaDisplayMode.used)
                Text("Remaining").tag(QuotaDisplayMode.remaining)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(preferences.mode == .used ? "Shows how much of your quota you’ve used." : "Shows how much of your quota is left.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Show both quota windows in the menu bar", isOn: $preferences.showsBothMenuBarQuotas)
                .toggleStyle(.checkbox)
            Text("For paired quotas, shows two percentages. Turn off to show the window closest to its limit.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("When quota is exhausted").font(.headline)
            Toggle("Show reset countdown in the menu bar", isOn: $preferences.showsResetCountdownInMenuBar)
                .toggleStyle(.checkbox)
            Toggle("Show reset countdown in the compact menu", isOn: $preferences.showsResetCountdownInCompactMenu)
                .toggleStyle(.checkbox)
            Text("Replaces exhausted percentages with a short time, such as 42m, 3h, or 2d. Uses the provider’s reset time.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Default menu view").font(.headline)
            Picker("Default menu view", selection: $preferences.defaultMenuView) {
                Text("Compact").tag(MenuViewMode.compact)
                Text("Expanded").tag(MenuViewMode.expanded)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(preferences.defaultMenuView == .compact ? "Option-click opens the expanded view." : "Option-click opens the compact view.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ProviderVisibilitySettingsView(preferences: preferences)
        }
    }
}

private struct AlertsHistorySettingsView: View {
    @Bindable var preferences: DisplayPreferences
    @Bindable var resetAlerts: QuotaResetAlerts

    var body: some View {
        SettingsPage {
            Text("Quota reset alerts").font(.headline)
            Toggle("Notify for session and rolling resets", isOn: $preferences.notifiesShortResets)
                .toggleStyle(.checkbox)
            Toggle("Notify for weekly and monthly resets", isOn: $preferences.notifiesLongResets)
                .toggleStyle(.checkbox)
            HStack {
                Toggle("Celebrate weekly and monthly resets", isOn: $preferences.celebratesLongResets)
                    .toggleStyle(.checkbox)
                Spacer(minLength: 8)
                Button("Preview", action: resetAlerts.previewConfetti)
            }
            Text("Alerts follow fresh quota readings. Rolling quota alerts wait until the allowance is fully available again.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Confetti lasts a few seconds, lets clicks pass through, and respects Reduce Motion. All three options are off by default.")
                .font(.caption).foregroundStyle(.secondary)
            if preferences.notifiesShortResets || preferences.notifiesLongResets || resetAlerts.issue != nil {
                Text(resetAlerts.statusText).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Usage history").font(.headline)
            Toggle("Record quota history", isOn: $preferences.recordsQuotaHistory)
                .toggleStyle(.checkbox)
            Text("Saves quota percentages at each refresh for the account hover graph. Keeps up to 30 days locally. Gaps remain while the app is closed or asleep.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Collect token usage", isOn: $preferences.tracksProxyUsage)
                .toggleStyle(.checkbox)
            Text("Enables usage statistics on your proxy and saves token totals locally while this app runs. Hover over an account for details.")
                .font(.caption).foregroundStyle(.secondary)
            Text("This app consumes the usage queue. Use one collector per proxy. Turning this off leaves the proxy’s statistics setting unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await resetAlerts.updateAuthorization() }
    }
}

private struct ConnectionSettingsView: View {
    @Bindable var preferences: DisplayPreferences
    @Bindable var updater: AppUpdater
    let onKeySaved: () -> Void
    @State private var endpointDraft = ""
    @State private var endpointError: String?
    @State private var keyDraft = ""
    @State private var keyMessage = "Stored in your macOS Keychain. The saved key stays hidden."
    @State private var keyFailed = false

    private func saveKey() {
        do {
            try ManagementKey.save(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            keyDraft = ""
            keyMessage = "Management key saved. Refreshing quotas…"
            keyFailed = false
            onKeySaved()
        } catch {
            keyMessage = error.localizedDescription
            keyFailed = true
        }
    }

    private func saveURL() {
        do {
            try preferences.saveEndpoint(endpointDraft)
            endpointDraft = preferences.endpoint
            endpointError = nil
        } catch { endpointError = error.localizedDescription }
    }

    var body: some View {
        SettingsPage {
            Text("Proxy URL").font(.headline)
            HStack {
                TextField("http://127.0.0.1:8317", text: $endpointDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveURL)
                Button("Apply", action: saveURL)
                    .disabled(endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines) == preferences.endpoint)
            }
            Text(endpointError ?? "Use your local or remote CLIProxyAPI URL. Prefer HTTPS for remote servers. A reverse-proxy path prefix is supported.")
                .font(.caption)
                .foregroundStyle(endpointError == nil ? Color.secondary : Color.red)
            Text("Management key").font(.headline)
            HStack {
                SecureField("CLIProxyAPI management key", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveKey)
                Button("Save", action: saveKey)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(keyMessage).font(.caption)
                .foregroundStyle(keyFailed ? Color.red : Color.secondary)
            Divider()
            Text("App updates").font(.headline)
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                .toggleStyle(.checkbox)
            Toggle("Automatically download and install updates", isOn: $updater.automaticallyInstallsUpdates)
                .toggleStyle(.checkbox)
                .disabled(!updater.automaticallyChecksForUpdates)
            Text("Signed updates from GitHub Releases.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { endpointDraft = preferences.endpoint }
    }
}
