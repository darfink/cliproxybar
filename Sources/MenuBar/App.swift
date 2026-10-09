import AppKit
import CLIProxyBarCore

@main
struct MenuBarApp {
    @MainActor static func main() {
        DisplayPreferences.migrateLegacyDefaults()
        if CommandLine.arguments.contains("--store-key") {
            do { try ManagementKey.save(readLine(strippingNewline: true) ?? ""); print("Management key saved in Keychain.") }
            catch { print(error.localizedDescription); exit(1) }
            return
        }
        let endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? "http://127.0.0.1:8317"
        guard let client = try? LocalProxyClient(endpoint: endpoint) else { print("Invalid proxy URL."); exit(1) }
        if CommandLine.arguments.contains("--check") {
            Task {
                do {
                    let accounts = try await client.fetch()
                    for account in accounts {
                        let quota = try await client.fetchQuota(for: account)
                        print("\(account.provider): \(quota.models.map { "\($0.name)=\(Int($0.percentage))% remaining" }.joined(separator: ", "))")
                    }
                    print("Connected: \(accounts.count) accounts")
                    exit(0)
                } catch { print(error.localizedDescription); exit(1) }
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        let delegate = MenuBarDelegate(client: client)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class MenuBarDelegate: NSObject, NSApplicationDelegate {
    var client: LocalProxyClient
    let statusBar = StatusBarManager()
    let preferences = DisplayPreferences()
    let updater = AppUpdater()
    lazy var settingsWindow = SettingsWindow(preferences: preferences, updater: updater, onKeySaved: { [weak self] in
        self?.applyEndpoint()
    })
    var commands: StatusBarCommandDispatcher!
    var accounts: [ProxyAccount] = []
    var cachedOnLaunch = 0
    var cache: QuotaCache
    var endpointGeneration = 0
    var connected = false
    var refreshing = false
    var message = "Connecting to CLIProxyAPI…"
    var selected: QuotaProvider?
    var pollTask: Task<Void, Never>?
    var usageCollector: ProxyUsageCollector
    init(client: LocalProxyClient) {
        self.client = client
        cache = QuotaCache(endpoint: client.baseURL.absoluteString)
        usageCollector = ProxyUsageCollector(client: client)
        super.init()
        do {
            accounts = try cache.load()
            cachedOnLaunch = accounts.count
        } catch { message = "Saved readings could not be loaded. Fetching fresh quotas…" }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--smoke-updater-test") {
            guard !updater.automaticallyChecksForUpdates else {
                print("Pass -SUEnableAutomaticChecks NO for the updater diagnostic.")
                exit(1)
            }
            updater.start()
            print("Updater initialized: \(updater.canCheckForUpdates)")
            exit(updater.canCheckForUpdates ? 0 : 1)
        }
        let isDiagnostic = CommandLine.arguments.contains { ["--smoke-test", "--smoke-cache-test"].contains($0) }
        if !isDiagnostic { updater.start() }
        preferences.onChange = { [weak self] in self?.render() }
        preferences.onEndpointChange = { [weak self] in self?.applyEndpoint() }
        preferences.onUsageTrackingChange = { [weak self] in self?.applyUsageTracking() }
        usageCollector.onChange = { [weak self] in self?.statusBar.invalidateMenuContent() }
        commands = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(
            refreshAll: { [weak self] in await self?.refresh() },
            refreshProvider: { [weak self] provider in await self?.refresh(provider: provider.rawValue) },
            refreshAccount: { [weak self] account in await self?.refresh(accountName: account.accountKey) },
            toggleProxy: {}, toggleTunnel: { _ in },
            copyText: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString($0, forType: .string) },
            switchAntigravityAccount: { _ in }, isAntigravityIDERunning: { false }, confirmAntigravitySwitch: { _, _ in false },
            selectProvider: { [weak self] provider in self?.selected = provider },
            settings: { [weak self] in
                self?.statusBar.closeMenu()
                DispatchQueue.main.async { self?.settingsWindow.show() }
            },
            openApp: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.client.baseURL.appendingPathComponent("management.html"))
            },
            quit: { NSApplication.shared.terminate(nil) }, menuNeedsRebuild: { [weak self] in self?.render() }
        ))
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(commands.settingsMenuItem())
        appMenu.addItem(commands.refreshMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CLIProxyBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApplication.shared.mainMenu = mainMenu
        if CommandLine.arguments.contains("--settings") { settingsWindow.show() }
        statusBar.configureMenu(snapshotProvider: { [unowned self] in snapshot() }, commandDispatcher: commands)
        render()
        do { _ = try ManagementKey.read() }
        catch LocalClientError.missingKey { settingsWindow.show() }
        catch { /* The refresh result reports Keychain errors without changing settings. */ }
        if CommandLine.arguments.contains("--smoke-cache-test") {
            let menu = StatusBarMenuRenderer(snapshot: snapshot(), commands: commands).buildMenu()
            print("Offline startup: cachedAccounts=\(cachedOnLaunch), menuItems=\(menu.items.count)")
            exit(cachedOnLaunch > 0 && accounts.allSatisfy { !$0.providerQuota().models.isEmpty } ? 0 : 1)
        }
        if !CommandLine.arguments.contains("--smoke-test") { applyUsageTracking() }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        pollTask?.cancel()
        usageCollector.stop()
    }

    private func applyUsageTracking() {
        if preferences.tracksProxyUsage { usageCollector.start() }
        else { usageCollector.stop() }
        render()
    }
    private func applyEndpoint() {
        guard let newClient = try? LocalProxyClient(endpoint: preferences.endpoint) else { return }
        endpointGeneration += 1
        client = newClient
        usageCollector.stop()
        usageCollector = ProxyUsageCollector(client: newClient)
        usageCollector.onChange = { [weak self] in self?.statusBar.invalidateMenuContent() }
        applyUsageTracking()
        cache = QuotaCache(endpoint: newClient.baseURL.absoluteString)
        accounts = (try? cache.load()) ?? []
        selected = nil
        connected = false
        refreshing = false
        message = "Connecting to CLIProxyAPI…"
        render()
        Task { [weak self] in await self?.refresh() }
    }

    func refresh(provider: String? = nil, accountName: String? = nil) async {
        guard !refreshing else { return }
        refreshing = true
        let generation = endpointGeneration
        let client = self.client
        render()
        do {
            let fresh = try await client.fetch()
            guard generation == endpointGeneration else { return }
            accounts = QuotaCache.merging(fresh, previous: accounts)
            connected = true
            render()
            let targets = accounts.filter {
                ActiveQuotaParser.supports($0.provider) && $0.disabled != true &&
                (provider == nil || $0.provider == provider) && (accountName == nil || $0.name == accountName)
            }
            await withTaskGroup(of: (String, ProviderQuota?, String?).self) { group in
                for account in targets {
                    group.addTask { [client] in
                        do { return (account.name, try await client.fetchQuota(for: account), nil) }
                        catch {
                            let issue = error is LocalClientError ? error.localizedDescription : "Quota request failed. Previous readings are retained."
                            return (account.name, nil, issue)
                        }
                    }
                }
                for await (name, quota, issue) in group {
                    guard generation == endpointGeneration else { group.cancelAll(); return }
                    guard let index = accounts.firstIndex(where: { $0.name == name }) else { continue }
                    if let quota { accounts[index].fetchedQuota = quota }
                    accounts[index].quotaIssue = issue
                    render()
                }
            }
            guard generation == endpointGeneration else { return }
            let failures = accounts.filter { $0.quotaIssue != nil }.count
            message = "Connected • refreshed " + Date().formatted(date: .omitted, time: .shortened)
            message += failures == 0 ? "\nQuotas fetched directly from providers." : "\nSome quota requests failed. Previous readings are retained."
            do { try cache.save(accounts) }
            catch { message += "\nCould not save readings for the next launch." }
        } catch {
            guard generation == endpointGeneration else { return }
            connected = false
            message = error is LocalClientError ? error.localizedDescription : "Cannot reach CLIProxyAPI. Check the proxy URL and that management access is enabled."
            if !accounts.isEmpty { message += "\nShowing previous readings." }
            for index in accounts.indices { accounts[index].quotaIssue = "Proxy unavailable · previous reading" }
        }
        refreshing = false
        render()
        if CommandLine.arguments.contains("--smoke-test") {
            let compact = StatusBarMenuRenderer(snapshot: snapshot(), commands: commands).buildMenu()
            let expanded = StatusBarMenuRenderer(snapshot: snapshot(), commands: commands, expanded: true).buildMenu()
            let compactHeight = compact.items.compactMap { $0.view?.frame.height }.reduce(0, +)
            let expandedHeight = expanded.items.compactMap { $0.view?.frame.height }.reduce(0, +)
            print("Startup: connected=\(connected), accounts=\(accounts.count), compact=\(compact.items.count) items/\(compactHeight)pt, expanded=\(expanded.items.count) items/\(expandedHeight)pt")
            for account in accounts {
                if let resets = account.providerQuota().availableResetCredits { print("Codex resets available: \(resets)") }
                print("\(account.provider): metrics=\(account.providerQuota().models.count), refresh=\(account.quotaIssue == nil ? "ok" : "failed")")
            }
            print("Cached accounts on launch: \(cachedOnLaunch)")
            let refreshed = accounts.filter { ActiveQuotaParser.supports($0.provider) && $0.disabled != true }
            exit(connected && !compact.items.isEmpty && compactHeight < expandedHeight && refreshed.allSatisfy { $0.quotaIssue == nil && !$0.providerQuota().models.isEmpty } ? 0 : 1)
        }
    }
    func snapshot() -> StatusBarMenuSnapshot {
        let groups = Dictionary(grouping: accounts.filter { QuotaProvider(rawValue: $0.provider) != nil }, by: { QuotaProvider(rawValue: $0.provider)! })
        let providers = groups.keys.sorted { $0.rawValue < $1.rawValue }.map { provider in
            StatusBarMenuProviderSnapshot(provider: provider, accounts: (groups[provider] ?? []).map { account in
                StatusBarMenuAccountSnapshot(id: QuotaAccountID(provider: provider, accountKey: account.name), email: account.displayName, quota: account.providerQuota(), subscription: nil, isActiveInIDE: false, isRefreshing: refreshing, isRefreshBlocked: refreshing, refreshIssue: account.quotaIssue, proxyUsage: usageCollector.snapshot(for: account))
            }, isRefreshing: refreshing, supportsScopedRefresh: true)
        }
        return StatusBarMenuSnapshot(connectionMessage: message, isLocalProxyMode: client.isLoopback, proxyPort: UInt16(client.baseURL.port ?? client.defaultPort), isProxyRunning: connected, tunnel: CloudflareTunnelSnapshot(), providers: providers, selectedProvider: selected, isLoadingQuotas: refreshing, displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: preferences.mode, quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest), appearanceMode: .system, language: .english, proxyAddress: client.displayAddress)
    }
    func render() {
        let hasReadings = accounts.contains { !$0.providerQuota().models.isEmpty }
        let items = accounts.compactMap { account -> MenuBarQuotaDisplayItem? in
            guard let provider = QuotaProvider(rawValue: account.provider), preferences.showsInMenuBar(provider) else { return nil }
            let quota = account.providerQuota()
            return MenuBarQuotaDisplayItem(id: account.name, providerSymbol: provider.menuBarSymbol, accountShort: "", percentage: quota.models.map(\.percentage).min() ?? -1, provider: provider, isForbidden: quota.isForbidden, quotaPair: MenuBarQuotaPair.resolve(for: provider, from: quota.models))
        }
        statusBar.updateStatusBar(items: items, colorMode: .monochrome, quotaDisplayMode: preferences.mode, isRunning: connected || hasReadings, showMenuBarIcon: true, showQuota: hasReadings, appearanceMode: .system, language: .english, isRefreshing: refreshing)
        statusBar.rebuildMenuInPlace()
    }
}
