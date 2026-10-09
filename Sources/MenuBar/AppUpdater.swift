import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    var canCheckForUpdates = false
    private var automaticChecks = false
    private var automaticDownloads = false

    var automaticallyChecksForUpdates: Bool {
        get { automaticChecks }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyInstallsUpdates: Bool {
        get { automaticDownloads }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        observe(\.canCheckForUpdates) { $0.canCheckForUpdates = $1 }
        observe(\.automaticallyChecksForUpdates) { $0.automaticChecks = $1 }
        observe(\.automaticallyDownloadsUpdates) { $0.automaticDownloads = $1 }
    }

    private func observe(_ keyPath: KeyPath<SPUUpdater, Bool>, changed: @escaping @MainActor @Sendable (AppUpdater, Bool) -> Void) {
        observations.append(controller.updater.observe(keyPath, options: [.initial, .new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                changed(self, value)
            }
        })
    }

    func start() {
        // SwiftPM executables used during development are not installable app bundles.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
