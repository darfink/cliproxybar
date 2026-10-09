import AppKit
import SwiftUI
import CLIProxyBarCore

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let preferences: DisplayPreferences
    private let onKeySaved: () -> Void
    init(preferences: DisplayPreferences, onKeySaved: @escaping () -> Void) {
        self.preferences = preferences
        self.onKeySaved = onKeySaved
    }

    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 610), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "CLIProxyBar Settings"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: DisplaySettingsView(preferences: preferences, onKeySaved: onKeySaved, close: { [weak panel] in panel?.close() }))
            panel.center()
            window = panel
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct DisplaySettingsView: View {
    @Bindable var preferences: DisplayPreferences
    let onKeySaved: () -> Void
    let close: () -> Void
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
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quota display").font(.headline)
                    Picker("Quota display", selection: $preferences.mode) {
                        Text("Usage").tag(QuotaDisplayMode.used)
                        Text("Remaining").tag(QuotaDisplayMode.remaining)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(preferences.mode == .used ? "Shows how much of your quota you’ve used." : "Shows how much of your quota is left.")
                        .font(.callout).foregroundStyle(.secondary)
                    Divider()
                    Text("Providers in the menu bar").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(QuotaProvider.allCases.filter { ActiveQuotaParser.supports($0.rawValue) }) { provider in
                            Toggle(provider.displayName, isOn: Binding(
                                get: { preferences.showsInMenuBar(provider) },
                                set: { preferences.setMenuBarVisible($0, for: provider) }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                    Text("The dropdown still shows every account. Turn all off for just the app icon.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Proxy usage history").font(.headline)
                    Toggle("Collect token usage", isOn: $preferences.tracksProxyUsage)
                        .toggleStyle(.checkbox)
                    Text("Enables usage statistics on your proxy and saves token totals locally while this app runs. Hover over an account for details.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("This app consumes the usage queue. Use one collector per proxy. Turning this off leaves the proxy’s statistics setting unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Local proxy URL").font(.headline)
                    HStack {
                        TextField("http://127.0.0.1:8317", text: $endpointDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveURL)
                        Button("Apply", action: saveURL)
                            .disabled(endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines) == preferences.endpoint)
                    }
                    Text(endpointError ?? "Use http://localhost or a loopback IP, with your proxy port.")
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            HStack {
                Text("CLIProxyBar · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { endpointDraft = preferences.endpoint }
        .padding(20)
        .frame(width: 440, height: 610)
    }
}
