import SwiftUI
import Observation
import CLIProxyBarCore

@MainActor @Observable
final class AccountSettingsModel {
    private(set) var accounts: [ProxyAccount] = []
    private(set) var busy = false
    private(set) var issue: String?
    private(set) var message: String?
    private var generation = 0
    private var endpoint: String?

    func reload(client: LocalProxyClient) async {
        generation += 1
        let operation = generation
        endpoint = client.baseURL.absoluteString
        accounts = []
        busy = true
        issue = nil
        message = nil
        do {
            let fresh = try await client.fetch()
            guard operation == generation else { return }
            accounts = fresh.sorted { ($0.provider, $0.displayName, $0.name) < ($1.provider, $1.displayName, $1.name) }
        } catch {
            guard operation == generation else { return }
            issue = error.localizedDescription
        }
        busy = false
    }

    func remove(_ account: ProxyAccount, client: LocalProxyClient,
                didRemove: (ProxyAccount, URL) -> Void) async {
        guard !busy, endpoint == client.baseURL.absoluteString,
              accounts.contains(where: { $0.identity == account.identity }) else { return }
        let operation = generation
        busy = true
        issue = nil
        message = nil
        do {
            try await client.removeCredential(account)
            // Notify the app even if Settings changed endpoints during the request.
            // The receiver checks the endpoint before updating its own account list.
            didRemove(account, client.baseURL)
            guard operation == generation else { return }
            accounts.removeAll { $0.identity == account.identity }
            message = "Credential removed from CLIProxyAPI."
        } catch {
            guard operation == generation else { return }
            issue = error.localizedDescription
        }
        busy = false
    }
}

struct AccountSettingsView: View {
    let endpoint: String
    let didRemove: (ProxyAccount, URL) -> Void
    var isActive = true
    @State private var model = AccountSettingsModel()
    @State private var pending: ProxyAccount?
    @State private var pendingEndpoint: String?
    @State private var confirmsRemoval = false

    var body: some View {
        AccountSettingsContent(model: model, reload: { Task { await reload() } }, remove: { account in
            pending = account
            pendingEndpoint = endpoint
            confirmsRemoval = true
        })
        .task(id: endpoint + (isActive ? "|active" : "|inactive")) {
            confirmsRemoval = false
            pending = nil
            guard isActive else { return }
            await reload()
        }
        .alert("Remove credential from CLIProxyAPI?", isPresented: $confirmsRemoval, presenting: pending) { account in
            Button("Remove credential", role: .destructive) {
                guard pendingEndpoint == endpoint, let client = try? LocalProxyClient(endpoint: endpoint) else { return }
                Task { await model.remove(account, client: client, didRemove: didRemove) }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { account in
            Text("Remove \(account.name) from \(endpoint)? CLIProxyAPI will stop using this credential. This affects every client of that proxy. You must add it again to restore access.")
        }
    }

    private func reload() async {
        guard let client = try? LocalProxyClient(endpoint: endpoint) else { return }
        await model.reload(client: client)
    }
}

struct AccountSettingsContent: View {
    @Bindable var model: AccountSettingsModel
    let reload: () -> Void
    let remove: (ProxyAccount) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts").font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Reload", action: reload).disabled(model.busy)
            }
            Text("Credentials on your connected CLIProxyAPI. To hide a provider instead, use provider visibility in Display.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.accounts.isEmpty && !model.busy && model.issue == nil {
                        Text("No accounts found.").foregroundStyle(.secondary).padding(.vertical)
                    }
                    ForEach(model.accounts, id: \.identity) { account in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.displayName).fontWeight(.semibold).textSelection(.enabled)
                                    Text(account.providerDisplayName ?? QuotaProvider(rawValue: account.provider)?.displayName ?? account.provider)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if account.canRemoveCredential {
                                    Button("Remove…", role: .destructive) {
                                        remove(account)
                                    }.disabled(model.busy)
                                }
                            }
                            if account.canRemoveCredential {
                                Text(account.name).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    .textSelection(.enabled).lineLimit(2)
                                Text(account.disabled == true ? "Disabled" : "Credential file")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("No removable credential file. Manage this account in CLIProxyAPI.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let issue = model.issue { Text(issue).font(.callout).foregroundStyle(.red) }
            if let message = model.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            Text("Removing a credential stops proxy routing through it. Plugin keys still in proxy configuration may reappear. Saved usage history is kept.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
