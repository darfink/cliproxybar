import AppKit
import CLIProxyBarCore

@MainActor
enum StatusBarCommand: Equatable {
    case refreshAll
    case refreshProvider(QuotaProvider)
    case refreshAccount(QuotaAccountID)
    case toggleProxy
    case toggleTunnel(port: UInt16)
    case copyProxyURL(String)
    case copyTunnelURL(String)
    case useAntigravityAccount(email: String)
    case selectProvider(QuotaProvider?)
    case settings
    case openApp
    case quit
}

@MainActor
public struct StatusBarCommandHandlers {
    fileprivate let refreshAll: @MainActor @Sendable () async -> Void
    fileprivate let refreshProvider: @MainActor @Sendable (QuotaProvider) async -> Void
    fileprivate let refreshAccount: @MainActor @Sendable (QuotaAccountID) async -> Void
    fileprivate let toggleProxy: @MainActor @Sendable () async -> Void
    fileprivate let toggleTunnel: @MainActor @Sendable (UInt16) async -> Void
    fileprivate let copyText: (String) -> Void
    fileprivate let switchAntigravityAccount: @MainActor @Sendable (String) async -> Void
    fileprivate let isAntigravityIDERunning: () -> Bool
    fileprivate let confirmAntigravitySwitch: (_ email: String, _ isIDERunning: Bool) -> Bool
    fileprivate let selectProvider: (QuotaProvider?) -> Void
    fileprivate let settings: () -> Void
    fileprivate let openApp: () -> Void
    fileprivate let quit: () -> Void
    fileprivate let menuNeedsRebuild: () -> Void

    public init(
        refreshAll: @escaping @MainActor @Sendable () async -> Void,
        refreshProvider: @escaping @MainActor @Sendable (QuotaProvider) async -> Void,
        refreshAccount: @escaping @MainActor @Sendable (QuotaAccountID) async -> Void,
        toggleProxy: @escaping @MainActor @Sendable () async -> Void,
        toggleTunnel: @escaping @MainActor @Sendable (UInt16) async -> Void,
        copyText: @escaping (String) -> Void,
        switchAntigravityAccount: @escaping @MainActor @Sendable (String) async -> Void,
        isAntigravityIDERunning: @escaping () -> Bool,
        confirmAntigravitySwitch: @escaping (_ email: String, _ isIDERunning: Bool) -> Bool,
        selectProvider: @escaping (QuotaProvider?) -> Void,
        settings: @escaping () -> Void,
        openApp: @escaping () -> Void,
        quit: @escaping () -> Void,
        menuNeedsRebuild: @escaping () -> Void
    ) {
        self.refreshAll = refreshAll
        self.refreshProvider = refreshProvider
        self.refreshAccount = refreshAccount
        self.toggleProxy = toggleProxy
        self.toggleTunnel = toggleTunnel
        self.copyText = copyText
        self.switchAntigravityAccount = switchAntigravityAccount
        self.isAntigravityIDERunning = isAntigravityIDERunning
        self.confirmAntigravitySwitch = confirmAntigravitySwitch
        self.selectProvider = selectProvider
        self.settings = settings
        self.openApp = openApp
        self.quit = quit
        self.menuNeedsRebuild = menuNeedsRebuild
    }
}

@MainActor
public final class StatusBarCommandDispatcher: NSObject {
    private let handlers: StatusBarCommandHandlers

    public init(handlers: StatusBarCommandHandlers) {
        self.handlers = handlers
        super.init()
    }

    func settingsMenuItem(hidden: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        item.keyEquivalentModifierMask = .command
        item.target = self
        item.isHidden = hidden
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    func refreshMenuItem(hidden: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: "Refresh Quotas", action: #selector(refreshQuotas), keyEquivalent: "r")
        item.keyEquivalentModifierMask = .command
        item.target = self
        item.isHidden = hidden
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    @objc private func refreshQuotas() { dispatch(.refreshAll) }

    @objc private func openSettings() { handlers.settings() }

    func dispatch(_ command: StatusBarCommand) {
        switch command {
        case .refreshAll:
            perform(handlers.refreshAll)
        case .refreshProvider(let provider):
            perform { [handlers] in await handlers.refreshProvider(provider) }
        case .refreshAccount(let account):
            perform { [handlers] in await handlers.refreshAccount(account) }
        case .toggleProxy:
            perform(handlers.toggleProxy)
        case .toggleTunnel(let port):
            perform { [handlers] in await handlers.toggleTunnel(port) }
        case .copyProxyURL(let url), .copyTunnelURL(let url):
            handlers.copyText(url)
        case .useAntigravityAccount(let email):
            guard handlers.confirmAntigravitySwitch(email, handlers.isAntigravityIDERunning()) else {
                return
            }
            perform { [handlers] in await handlers.switchAntigravityAccount(email) }
        case .selectProvider(let provider):
            handlers.selectProvider(provider)
        case .settings:
            handlers.settings()
        case .openApp:
            handlers.openApp()
        case .quit:
            handlers.quit()
        }
    }

    private func perform(_ action: @escaping @MainActor @Sendable () async -> Void) {
        Task { [handlers] in
            await action()
            handlers.menuNeedsRebuild()
        }
    }
}
