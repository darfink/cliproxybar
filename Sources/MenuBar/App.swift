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
                    let plugins = try await client.fetchQuotaProviders()
                    for account in accounts where account.disabled != true {
                        guard ActiveQuotaParser.supports(account, pluginProviders: plugins.identifiers) else {
                            print("\(account.provider): no quota API; usage history remains available")
                            continue
                        }
                        let quota = try await client.fetchQuota(for: account, pluginProviders: plugins.identifiers)
                        print("\(account.provider): \(quota.models.filter { $0.percentage >= 0 }.map { "\($0.name)=\(Int($0.percentage))% remaining" }.joined(separator: ", "))")
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
    let resetAlerts = QuotaResetAlerts()
    lazy var settingsWindow = SettingsWindow(preferences: preferences, updater: updater, resetAlerts: resetAlerts, onKeySaved: { [weak self] in
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
    var quotaRegistry = QuotaProviderRegistry()
    var quotaDiscoveryIssue: String?
    var pollTask: Task<Void, Never>?
    var resetRefreshTask: Task<Void, Never>?
    var resetMonitor: QuotaResetMonitor
    var usageCollector: ProxyUsageCollector
    init(client: LocalProxyClient) {
        self.client = client
        cache = QuotaCache(endpoint: client.baseURL.absoluteString)
        resetMonitor = QuotaResetMonitor(endpoint: client.baseURL.absoluteString)
        try? resetMonitor.load()
        usageCollector = ProxyUsageCollector(client: client)
        super.init()
        do {
            accounts = try cache.load()
            preferences.updateAvailableProviders(accounts)
            cachedOnLaunch = accounts.count
        } catch { message = "Saved readings could not be loaded. Fetching fresh quotas…" }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--smoke-notifications-test") {
            guard Bundle.main.bundleURL.pathExtension == "app" else {
                print("Run the notification diagnostic from an app bundle.")
                exit(1)
            }
            Task {
                for _ in 0..<5 { await resetAlerts.updateAuthorization() }
                print("Native notification settings read successfully, without requesting permission or delivering alerts.")
                exit(0)
            }
            return
        }
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
        preferences.onResetAlertsChange = { [weak self] in
            guard let self else { return }
            Task { await self.resetAlerts.updateAuthorization(requestIfNeeded:
                self.preferences.notifiesShortResets || self.preferences.notifiesLongResets) }
        }
        usageCollector.onChange = { [weak self] in self?.statusBar.invalidateMenuContent() }
        commands = StatusBarCommandDispatcher(handlers: StatusBarCommandHandlers(
            refreshAll: { [weak self] in await self?.refresh() },
            refreshProvider: { [weak self] provider in await self?.refresh(provider: provider.rawValue) },
            refreshAccount: { [weak self] account in await self?.refresh(provider: account.provider.rawValue, accountName: account.accountKey) },
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
            exit(cachedOnLaunch > 0 && accounts.allSatisfy { $0.fetchedQuota != nil } ? 0 : 1)
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
        resetRefreshTask?.cancel()
        resetAlerts.stop()
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
        resetRefreshTask?.cancel()
        client = newClient
        usageCollector.stop()
        usageCollector = ProxyUsageCollector(client: newClient)
        usageCollector.onChange = { [weak self] in self?.statusBar.invalidateMenuContent() }
        applyUsageTracking()
        cache = QuotaCache(endpoint: newClient.baseURL.absoluteString)
        resetMonitor = QuotaResetMonitor(endpoint: newClient.baseURL.absoluteString)
        try? resetMonitor.load()
        accounts = (try? cache.load()) ?? []
        quotaRegistry = QuotaProviderRegistry()
        quotaDiscoveryIssue = nil
        preferences.updateAvailableProviders(accounts)
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
            preferences.updateAvailableProviders(accounts)
            connected = true
            render()
            do {
                let discovered = try await client.fetchQuotaProviders()
                guard generation == endpointGeneration else { return }
                quotaRegistry = discovered
                quotaDiscoveryIssue = nil
            } catch {
                quotaDiscoveryIssue = "Quota discovery failed. " + (error is LocalClientError ? error.localizedDescription : "The previous provider registry is retained.")
            }
            guard generation == endpointGeneration else { return }
            let pluginProviders = quotaRegistry.identifiers
            for index in accounts.indices {
                let account = accounts[index]
                if let metadata = quotaRegistry.entry(for: PluginQuotaParser.text(account.quota_provider) ?? account.provider) {
                    accounts[index].providerDisplayName = metadata.displayName
                } else if quotaDiscoveryIssue == nil {
                    accounts[index].providerDisplayName = nil
                }
                if !ActiveQuotaParser.supports(account, pluginProviders: pluginProviders) {
                    if quotaDiscoveryIssue == nil {
                        accounts[index].quotaState = .unsupported
                        accounts[index].quotaIssue = nil
                    } else {
                        accounts[index].recordQuotaFailure("Quota capability could not be checked. Previous readings are retained.")
                    }
                }
            }
            preferences.updateAvailableProviders(accounts)
            var resetEvents: [QuotaResetEvent] = []
            var fetchedCount = 0
            let targets = accounts.filter {
                ActiveQuotaParser.supports($0, pluginProviders: pluginProviders) && $0.disabled != true &&
                (provider == nil || QuotaProvider(rawValue: $0.provider) == QuotaProvider(rawValue: provider!)) && (accountName == nil || $0.name == accountName)
            }
            await withTaskGroup(of: (ProxyAccountIdentity, ProviderQuota?, String?, Bool).self) { group in
                for account in targets {
                    group.addTask { [client] in
                        do { return (account.identity, try await client.fetchQuota(for: account, pluginProviders: pluginProviders), nil, false) }
                        catch LocalClientError.quotaUnsupported {
                            return (account.identity, nil, LocalClientError.quotaUnsupported.localizedDescription, true)
                        }
                        catch {
                            let issue = error is LocalClientError ? error.localizedDescription : "Quota request failed. Previous readings are retained."
                            return (account.identity, nil, issue, false)
                        }
                    }
                }
                for await (identity, quota, issue, unsupported) in group {
                    guard generation == endpointGeneration else { group.cancelAll(); return }
                    guard let index = accounts.firstIndex(where: { $0.identity == identity }) else { continue }
                    if let quota {
                        accounts[index].recordQuota(quota)
                        fetchedCount += 1
                        if !CommandLine.arguments.contains("--smoke-test") {
                            resetEvents += resetMonitor.observe(account: accounts[index], quota: quota)
                        }
                    } else if let issue { accounts[index].recordQuotaFailure(issue, unsupported: unsupported) }
                    render()
                }
            }
            guard generation == endpointGeneration else { return }
            let failures = accounts.filter { $0.quotaReadState.isFailure }.count
            message = "Connected • refreshed " + Date().formatted(date: .omitted, time: .shortened)
            message += fetchedCount == 0 ? "\nNo quota readings fetched." : "\nQuota responses received for \(fetchedCount) account\(fetchedCount == 1 ? "" : "s")."
            if failures > 0 { message += "\nSome quota requests failed. Previous readings are retained." }
            if let quotaDiscoveryIssue { message += "\n" + quotaDiscoveryIssue }
            do { try cache.save(accounts) }
            catch { message += "\nCould not save readings for the next launch." }
            if !CommandLine.arguments.contains("--smoke-test") {
                do {
                    try resetMonitor.save()
                    await resetAlerts.deliver(resetEvents, preferences: preferences)
                } catch { message += "\nCould not save reset history. Reset alerts are paused for this refresh." }
            }
        } catch {
            guard generation == endpointGeneration else { return }
            connected = false
            message = error is LocalClientError ? error.localizedDescription : "Cannot reach CLIProxyAPI. Check the proxy URL and that management access is enabled."
            if !accounts.isEmpty { message += "\nShowing previous readings." }
            for index in accounts.indices { accounts[index].recordQuotaFailure("Proxy unavailable · previous reading") }
        }
        guard generation == endpointGeneration else { return }
        refreshing = false
        render()
        if !CommandLine.arguments.contains("--smoke-test") { scheduleResetRefresh() }
        if CommandLine.arguments.contains("--smoke-test") {
            let compact = StatusBarMenuRenderer(snapshot: snapshot(), commands: commands).buildMenu()
            let expanded = StatusBarMenuRenderer(snapshot: snapshot(), commands: commands, expanded: true).buildMenu()
            let compactHeight = compact.items.compactMap { $0.view?.frame.height }.reduce(0, +)
            let expandedHeight = expanded.items.compactMap { $0.view?.frame.height }.reduce(0, +)
            print("Startup: connected=\(connected), accounts=\(accounts.count), compact=\(compact.items.count) items/\(compactHeight)pt, expanded=\(expanded.items.count) items/\(expandedHeight)pt")
            for account in accounts {
                if let resets = account.providerQuota().availableResetCredits { print("Codex resets available: \(resets)") }
                print("\(account.provider): metrics=\(account.providerQuota().models.count), state=\(account.quotaReadState.rawValue)")
            }
            print("Cached accounts on launch: \(cachedOnLaunch)")
            let refreshed = accounts.filter { ActiveQuotaParser.supports($0, pluginProviders: quotaRegistry.identifiers) && $0.disabled != true }
            exit(connected && quotaDiscoveryIssue == nil && !compact.items.isEmpty && compactHeight < expandedHeight
                && refreshed.allSatisfy { !$0.quotaReadState.isFailure && $0.fetchedQuota != nil } ? 0 : 1)
        }
    }
    private func scheduleResetRefresh() {
        resetRefreshTask?.cancel()
        let now = Date()
        let next = accounts.filter { $0.disabled != true }.flatMap { $0.providerQuota().models }
            .filter { QuotaResetKind.classify($0.name) != nil }
            .map { ProxyAccount.observationDate($0.resetTime) }.filter { $0 > now }.min()
        guard let next else { resetRefreshTask = nil; return }
        resetRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(next.timeIntervalSince(now) + 2)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
    func snapshot() -> StatusBarMenuSnapshot {
        let providers = StatusBarMenuProviderSnapshot.grouping(accounts, refreshing: refreshing) { usageCollector.snapshot(for: $0) }
        return StatusBarMenuSnapshot(connectionMessage: message, isLocalProxyMode: client.isLoopback, proxyPort: UInt16(client.baseURL.port ?? client.defaultPort), isProxyRunning: connected, tunnel: CloudflareTunnelSnapshot(), providers: providers, selectedProvider: selected, isLoadingQuotas: refreshing, displaySettings: StatusBarMenuDisplaySettings(quotaDisplayMode: preferences.mode, quotaDisplayStyle: .lowestBar, hideSensitiveInfo: false, modelAggregationMode: .lowest), appearanceMode: .system, language: .english, proxyAddress: client.displayAddress, quotaDiscoveryIssue: quotaDiscoveryIssue)
    }
    func render() {
        let hasReadings = accounts.contains { $0.providerQuota().models.contains { $0.percentage >= 0 } }
        let items = accounts.compactMap { account -> MenuBarQuotaDisplayItem? in
            guard let provider = QuotaProvider(rawValue: account.provider), preferences.showsInMenuBar(provider) else { return nil }
            let quota = account.providerQuota()
            return MenuBarQuotaDisplayItem(id: account.name, providerSymbol: provider.menuBarSymbol, accountShort: "", percentage: quota.models.map(\.percentage).filter { $0 >= 0 }.min() ?? -1, provider: provider, isForbidden: quota.isForbidden, quotaPair: MenuBarQuotaPair.resolve(for: provider, from: quota.models))
        }
        statusBar.updateStatusBar(items: items, colorMode: .monochrome, quotaDisplayMode: preferences.mode, isRunning: connected || hasReadings, showMenuBarIcon: true, showQuota: hasReadings, appearanceMode: .system, language: .english, isRefreshing: refreshing)
        statusBar.rebuildMenuInPlace()
    }
}
