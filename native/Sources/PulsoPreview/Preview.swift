// Renders the panel to PNG with sample data, dark and light, with the first row hovered.
import AppKit
import PulsoCore
import PulsoUI
import SwiftUI

let outDir = "/tmp/pulso-preview-native"

/// Sample data shaped like the approved mockup: warning tone, five apps.
let baseSample = PanelView(
    memory: .init(percent: "85%", detail: "27.2 GB of 32.0 GB",
                  help: "How much memory is in use. A high number is normal on a Mac.", barPercent: 85.1),
    tone: .warning,
    advice: "Your Mac is starting to slow down. Quitting a heavy app below will help.",
    tiles: [
        .init(label: "Pressure", value: "Warning", help: "How hard your Mac is working to find free memory."),
        .init(label: "Swap", value: "20.0 GB", help: "Memory moved to the disk when it ran out of room."),
        .init(label: "CPU", value: "22%", help: "How busy the processor is right now."),
    ],
    sectionTitle: "Your apps using most memory",
    rows: [
        .init(pid: 1, name: "Google Chrome", memory: "5.7 GB", cpu: "23.1%", share: 1),
        .init(pid: 2, name: "Chrome", memory: "3.0 GB", cpu: "15.4%", share: 0.53, startedBy: "Raycast"),
        .init(pid: 3, name: "Slack", memory: "551.2 MB", cpu: "4.2%", share: 0.1),
        .init(pid: 4, name: "node", memory: "363.2 MB", cpu: "0.3%", share: 0.06),
        .init(pid: 5, name: "WindowServer", memory: "252.1 MB", cpu: "12.0%", share: 0.04),
    ],
    updated: "Updated 00:42:00 · refreshes every 3 s")

@MainActor func render(_ scheme: ColorScheme, _ name: String) {
    // Stand-in for the menu material the real window draws behind the panel.
    let backdrop = scheme == .dark ? Color(white: 0.17) : Color(white: 0.93)
    var sample = baseSample
    sample.openAtLogin = true
    let content = PanelContent(view: sample, highlightedPid: 1, onAction: { _ in })
        .background(backdrop)
        .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("PREVIEW_ERROR could not render \(name)")
        return
    }
    let path = "\(outDir)/\(name).png"
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("Preview written to \(path) (\(Int(image.size.width))×\(Int(image.size.height)) pt). Open it with Read.")
    } catch {
        print("PREVIEW_ERROR \(error)")
    }
}

@main struct Preview {
    @MainActor static func main() {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        render(.dark, "panel")
        render(.light, "panel-light")
        print("Compare with docs/panel-mockup.png (the approved design).")
    }
}
