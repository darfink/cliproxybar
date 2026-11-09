import AppKit
import SwiftUI
import XCTest
@testable import MenuBar

final class SettingsNavigationTests: XCTestCase {
    @MainActor
    func testSettingsSectionsStayVisibleInsideTheWindow() throws {
        _ = NSApplication.shared
        let suite = "SettingsNavigationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        var selected = SettingsSection.display
        let hosting = NSHostingView(rootView: SettingsLayout(selection: Binding(
            get: { selected }, set: { selected = $0 }
        )) {
            DisplaySettingsView(preferences: preferences)
        } footer: {
            HStack {
                Text("CLIProxyBar · Preview").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates…") {}
                Button("Done") {}.keyboardShortcut(.defaultAction)
            }
        }.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil; window.orderOut(nil) }
        func settle() {
            let deadline = Date().addingTimeInterval(0.15)
            while Date() < deadline {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        settle()
        let control = try XCTUnwrap(descendants(hosting).compactMap { $0 as? NSSegmentedControl }
            .first { $0.segmentCount == 4 })
        XCTAssertEqual((0..<4).map { control.label(forSegment: $0) }, SettingsSection.allCases.map(\.rawValue))
        XCTAssertFalse(control.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(hosting.bounds.contains(control.convert(control.bounds, to: hosting)))
        XCTAssertEqual(control.selectedSegment, 0)
        XCTAssertNil(window.toolbar, "Settings navigation must not migrate into an overflowing titlebar toolbar")
        if let path = ProcessInfo.processInfo.environment["CLIPROXYBAR_SETTINGS_PREVIEW"] {
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path + ".png"))
        }
        control.selectedSegment = 3
        if let action = control.action { control.sendAction(action, to: control.target) }
        XCTAssertEqual(selected, .connection, "Each section must be reachable directly from the visible strip")
    }
}
