import AppKit
import SwiftUI

struct ConfettiParticle {
    let x: Double
    let delay: Double
    let speed: Double
    let drift: Double
    let phase: Double
    let spin: Double
    let size: CGSize
    let color: Int

    static func make(seed: UInt64, count: Int = 150) -> [Self] {
        var state = seed
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64.max >> 11)
        }
        return (0..<count).map { index in
            Self(x: random(), delay: random() * 0.5, speed: 0.12 + random() * 0.1,
                 drift: (random() - 0.5) * 100, phase: random() * .pi * 2,
                 spin: (random() - 0.5) * 8, size: CGSize(width: 4 + random() * 4, height: 8 + random() * 5),
                 color: index % 6)
        }
    }
}

struct ConfettiCanvas: View {
    let particles: [ConfettiParticle]
    let elapsed: TimeInterval
    static let duration: TimeInterval = 3.6
    private let colors: [Color] = [.teal, .orange, .pink, .purple, .yellow, .blue]

    var body: some View {
        Canvas { context, size in
            guard elapsed >= 0, elapsed < Self.duration else { return }
            for particle in particles {
                let time = elapsed - particle.delay
                guard time > 0 else { continue }
                let x = particle.x * size.width + particle.drift * time + sin(time * 3 + particle.phase) * 18
                let y = -20 + size.height * (particle.speed * time + 0.055 * time * time)
                guard y < size.height + 20 else { continue }
                var drawing = context
                drawing.opacity = min(1, (Self.duration - elapsed) / 0.6)
                drawing.translateBy(x: x, y: y)
                drawing.rotate(by: .radians(particle.phase + particle.spin * time))
                let rect = CGRect(x: -particle.size.width / 2, y: -particle.size.height / 2,
                                  width: particle.size.width, height: particle.size.height)
                drawing.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[particle.color]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ConfettiAnimation: View {
    let startedAt: Date
    let particles: [ConfettiParticle]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { tick in
            ConfettiCanvas(particles: particles, elapsed: tick.date.timeIntervalSince(startedAt))
        }
    }
}

@MainActor
final class ConfettiPresenter {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    static func makePanel(frame: NSRect) -> NSPanel {
        let panel = ConfettiPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        return panel
    }

    @discardableResult
    func show() -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        guard panel == nil else { return true }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return false }
        let startedAt = Date()
        let particles = ConfettiParticle.make(seed: UInt64(startedAt.timeIntervalSince1970 * 1000))
        let panel = Self.makePanel(frame: screen.frame)
        panel.contentView = NSHostingView(rootView: ConfettiAnimation(startedAt: startedAt, particles: particles))
        self.panel = panel
        panel.orderFrontRegardless()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ConfettiCanvas.duration))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
        return true
    }

    func stop() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

private final class ConfettiPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
