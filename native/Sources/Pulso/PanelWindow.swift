// Pulso: the panel, an NSPanel holding the menu material behind SwiftUI's PanelContent.
import Cocoa
import PulsoCore
import PulsoUI
import SwiftUI

// A stretchable rounded mask: NSVisualEffectView clips its material only through maskImage.
@MainActor func roundedMask(_ radius: CGFloat) -> NSImage {
    let side = radius * 2 + 1
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
}

// The panel's view model: the single source the SwiftUI side reads while open.
final class PanelModel: ObservableObject {
    @Published private(set) var view: PanelView
    private(set) var lastSnapshot: Snapshot?

    init(_ initial: PanelView) {
        self.view = initial
    }

    // The latest update: rebuild the plain view, each row's hint naming what a click shows.
    func update(_ snapshot: Snapshot) {
        lastSnapshot = snapshot
        var view = buildPanelView(snapshot, refreshSeconds: 3)
        // A row's hint is the front plan for its app, so the tooltip is not a surprise.
        let groups = groupByApp(snapshot.processes)
        for i in view.rows.indices {
            guard let group = groups.first(where: { $0.pids.contains(view.rows[i].pid) }) else { continue }
            view.rows[i].hint = frontHint(frontPlan(group, host: frontHost(for: group)), name: view.rows[i].name)
        }
        // The login item's state, live, so the ✓ reflects what macOS currently reports.
        view.openAtLogin = loginIsOn(currentLoginStatus())
        self.view = view
    }
}

// SwiftUI's root view: renders the model's view and forwards any action back out.
struct PanelHost: View {
    @ObservedObject var model: PanelModel
    var onAction: (PanelAction) -> Void

    var body: some View {
        PanelContent(view: model.view, onAction: onAction)
    }
}

// A borderless NSPanel that may become key, so Escape and click-outside both reach it.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// The panel and everything it controls: a material-backed NSPanel under the status item.
@MainActor final class PanelWindow: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let viewModel: PanelModel
    private var panel: KeyPanel?
    private var hosting: NSHostingView<PanelHost>
    // Last time we closed via key loss, so a fast reopen is ignored (the toggle trap).
    private var lastResignClose: Date?
    // The escape key monitor, removed when the panel closes.
    private var keyMonitor: Any?

    // The panel's view model and hosting view, built on the main actor from the initial view.
    init(statusItem: NSStatusItem, onAction: @escaping (PanelAction) -> Void) {
        self.statusItem = statusItem
        self.viewModel = PanelModel(Self.initialPanelView())
        self.onAction = onAction
        self.hosting = NSHostingView(rootView: PanelHost(model: viewModel, onAction: { _ in }))
        super.init()
        hosting.rootView = PanelHost(model: viewModel, onAction: { [weak self] action in
            guard let self else { return }
            if action != .refresh && action != .toggleLogin { self.close() }
            self.onAction(action)
        })
    }

    // The action from the view, forwarded to the caller: close the panel first.
    var onAction: (PanelAction) -> Void

    // The initial view, built so the panel exists before the first real snapshot lands.
    private static func initialPanelView() -> PanelView {
        PanelView(
            memory: .init(percent: "", detail: "", help: "", barPercent: 0),
            tone: .normal,
            advice: nil,
            tiles: [.init(label: "", value: "", help: "")],
            sectionTitle: "",
            rows: [],
            updated: "")
    }

    // Feed a later update into the view model; the hosting view updates underneath.
    func update(_ snapshot: Snapshot) {
        viewModel.update(snapshot)
        buildPanelIfNeeded()
    }

    // The toggle: open when closed, close when open, guarding the resign-key reopen trap.
    @objc func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            if let last = lastResignClose, Date().timeIntervalSince(last) < 0.3 { return }
            open()
        }
    }

    // Open it: set up escape once, size it to the content, position it, raise it.
    private func open() {
        buildPanelIfNeeded()
        if keyMonitor == nil { setupEscape() }
        let fitting = hosting.fittingSize
        guard let panel else {
            NSLog("Pulso: panel window was not built")
            return
        }
        guard let screen = statusItem.button?.window?.screen else {
            NSLog("Pulso: status item button has no screen")
            return
        }
        guard let frame = panelFrame(for: screen, fitting: fitting) else {
            NSLog("Pulso: could not compute the panel frame")
            return
        }
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
    }

    // Close it: hide the panel, drop the key monitor, clear the trap (created once).
    public func close() {
        panel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // Create the window once: the panel and its material, then fill it with the hosting view.
    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        let panel = KeyPanel()
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.maskImage = roundedMask(10)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        panel.contentView = effect
        panel.setContentSize(NSSize(width: hosting.fittingSize.width, height: hosting.fittingSize.height))
        self.panel = panel
        setupEscape()
    }

    // Watch for Escape while open: swallow keyCode 53, forward every other key.
    private func setupEscape() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
                if key == "r" { self?.onAction(.refresh); return nil }
                if key == "q" { self?.onAction(.quitPulso); return nil }
            }
            if event.keyCode == 53 { self?.close() }
            return event.keyCode == 53 ? nil : event
        }
    }

    // Close on key loss (click outside): stamp the time, then hide the panel.
    @objc public func windowDidResignKey(_ notification: Notification) {
        lastResignClose = Date()
        close()
    }

    // The frame to place under the button: centred on it, bottom edge 4 pt above it.
    private func panelFrame(for screen: NSScreen?, fitting: NSSize) -> NSRect? {
        guard let button = statusItem.button else {
            NSLog("Pulso: status item has no button")
            return nil
        }
        guard let window = button.window else {
            NSLog("Pulso: status item button has no window")
            return nil
        }
        let converted = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(converted)
        let x = screenFrame.midX - fitting.width / 2
        let y = screenFrame.minY - 4 - fitting.height
        return clamp(NSRect(x: x, y: y, width: fitting.width, height: fitting.height), on: screen)
    }

    // The debug hook: open the panel, then measure and print one line after it renders.
    func debugPanel(exitNow: Bool) {
        open()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.measure()
            if exitNow { exit(0) }
        }
    }

    // One measured line in screen coordinates, then the panel's render as PNG.
    private func measure() {
        guard let panel, let button = statusItem.button else {
            print("PULSO_DEBUG_PANEL {\"error\":\"no panel\"}")
            return
        }
        let window = button.window
        let converted = button.convert(button.bounds, to: nil)
        let b = window?.convertToScreen(converted) ?? .zero
        let x = Int(panel.frame.origin.x)
        let y = Int(panel.frame.origin.y)
        let w = Int(panel.frame.width)
        let h = Int(panel.frame.height)
        let bx = Int(b.origin.x)
        let by = Int(b.origin.y)
        let bw = Int(b.width)
        let bh = Int(b.height)
        print("PULSO_DEBUG_PANEL {\"button\":{\"x\":\(bx),\"y\":\(by),\"w\":\(bw),\"h\":\(bh)},\"panel\":{\"x\":\(x),\"y\":\(y),\"w\":\(w),\"h\":\(h)},\"visible\":\(panel.isVisible),\"key\":\(panel.isKeyWindow)}")
        capturePanel()
    }

    // Render the hosting view to a PNG in the debug directory.
    private func capturePanel() {
        let dir = "/tmp/pulso-preview-native"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            NSLog("Pulso: could not capture the panel view")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            NSLog("Pulso: could not encode the panel as PNG")
            return
        }
        let url = URL(fileURLWithPath: "\(dir)/window.png")
        do { try png.write(to: url) } catch { NSLog("Pulso: could not write \(url): \(error)") }
    }

    // Position a frame under the button, clamped inside that screen's visible frame.
    private func clamp(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
        guard let screen else { return frame }
        let visible = screen.visibleFrame
        let x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        let y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }
}
