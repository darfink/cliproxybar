import Foundation

@MainActor
final class ProxyUsageCollector {
    private let client: LocalProxyClient
    private var history: ProxyUsageHistory
    private var task: Task<Void, Never>?
    private var historyLoaded = true
    private(set) var isEnabled = false
    private(set) var issue: String?
    private(set) var lastCollectedAt: Date?
    var onChange: (() -> Void)?

    init(client: LocalProxyClient) {
        self.client = client
        history = ProxyUsageHistory(endpoint: client.baseURL.absoluteString)
        do { try history.load() }
        catch {
            historyLoaded = false
            issue = "Saved usage history could not be loaded. Collection stopped to preserve the file."
        }
    }

    func start() {
        stop()
        isEnabled = true
        guard historyLoaded else { onChange?(); return }
        task = Task { [weak self] in
            guard let self else { return }
            var enabledStatistics = false
            while !Task.isCancelled {
                do {
                    if !enabledStatistics {
                        try await client.enableUsageStatistics()
                        try Task.checkCancellation()
                        history.start()
                        enabledStatistics = true
                    }
                    // Retry any failed save before consuming more queue records.
                    try history.save()
                    for _ in 0..<4 {
                        let events = try await client.fetchUsageEvents()
                        // Once fetched, save this batch even if collection was just paused.
                        history.ingest(events)
                        try history.save()
                        if events.count < 500 || Task.isCancelled { break }
                    }
                    lastCollectedAt = Date()
                    issue = nil
                } catch is CancellationError { return }
                catch {
                    issue = error is LocalClientError ? error.localizedDescription : "Usage collection interrupted. Saved totals are retained."
                }
                onChange?()
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isEnabled = false
    }

    func snapshot(for account: ProxyAccount) -> ProxyUsageSnapshot {
        history.snapshot(for: account, trackingEnabled: isEnabled, issue: issue, lastCollectedAt: lastCollectedAt)
    }
}
