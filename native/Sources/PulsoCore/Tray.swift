// PulsoCore: the menu bar item — title, icon, tooltip and glossary, a port of src/main/tray.ts.
import Foundation

/// The icon name by pressure alone, matching resources/: percent used plays no part.
public enum TrayIcon: String, Sendable { case template = "trayTemplate", warning = "trayWarning", critical = "trayCritical" }

/// The bar title: "RAM N%".
public func trayTitle(_ snapshot: Snapshot) -> String {
    "RAM \(Int(round(snapshot.memory.usedPercent)))%"
}

/// The icon name by pressure alone: the panel's snapshot already carries pressure.
public func trayIcon(_ snapshot: Snapshot) -> TrayIcon {
    switch snapshot.memory.pressure {
    case .normal: return .template
    case .warning: return .warning
    case .critical: return .critical
    }
}

/// The hover line: memory, cpu and swap spelled out for a read at a glance.
public func trayTooltip(_ snapshot: Snapshot) -> String {
    let mem = formatBytes(snapshot.memory.usedBytes)
    let total = formatBytes(snapshot.memory.totalBytes)
    let swap = formatBytes(snapshot.memory.swapUsedBytes)
    return "Memory \(mem) of \(total) · CPU \(fraction(snapshot.cpuPercent))% · Swap \(swap)"
}

/// The glossary shown by "What do these mean?"; the text lives here, index.ts only shows it.
public func helpDialog() -> (message: String, detail: String) {
    let detail = """
    Memory used: How much of your Mac's memory is in use right now. A high number is normal: macOS keeps memory busy on purpose so apps open faster.

    Memory pressure: How hard your Mac is working to find free memory.
    • Normal: all good.
    • Warning: your Mac is starting to slow down. Closing a heavy app will help.
    • Critical: close an app now.

    Swap: Memory your Mac has moved to the disk because it ran out of room. A little is fine. Many GB means your Mac is short of memory, and things will feel slower.

    CPU: How busy the processor is right now.

    Your apps using most memory: The apps of yours taking the most memory. Click one to bring it to the front, or Quit to close it.

    Icon colour: Plain means normal. Orange means warning. Red means critical.
    """
    return (message: "What do these mean?", detail: detail)
}
