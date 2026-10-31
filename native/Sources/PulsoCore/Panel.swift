// PulsoCore: the panel view model, the quit prompt and the snapshot, a port of src/main/panel.ts.
import Foundation

/// One reading the panel consumes: the time, a memory snapshot, cpu and the process list.
public struct Snapshot: Sendable {
    public let takenAt: Date
    public let memory: MemoryReading
    public let cpuPercent: Double
    public let processes: [ProcessSample]
    public let cores: Int

    public init(takenAt: Date, memory: MemoryReading, cpuPercent: Double, processes: [ProcessSample], cores: Int = 1) {
        self.takenAt = takenAt
        self.memory = memory
        self.cpuPercent = cpuPercent
        self.processes = processes
        self.cores = cores
    }
}

/// The plain data a panel renders: the memory header, tone, tiles, rows and footer.
public struct PanelView: Equatable, Sendable {
    public struct Memory: Equatable, Sendable {
        public let percent: String
        public let detail: String
        public let help: String
        public let barPercent: Double

        public init(percent: String, detail: String, help: String, barPercent: Double) {
            self.percent = percent
            self.detail = detail
            self.help = help
            self.barPercent = barPercent
        }
    }

    public struct Tile: Equatable, Sendable {
        public let label: String
        public let value: String
        public let help: String

        public init(label: String, value: String, help: String) {
            self.label = label
            self.value = value
            self.help = help
        }
    }

    public struct Row: Equatable, Sendable {
        public let pid: Int32
        public let name: String
        public let memory: String
        public let cpu: String
        public let share: Double
        public let startedBy: String?
        // What a click brings to the front, shown before the click as the tooltip.
        public var hint: String?

        public init(pid: Int32, name: String, memory: String, cpu: String, share: Double, startedBy: String? = nil, hint: String? = nil) {
            self.pid = pid
            self.name = name
            self.memory = memory
            self.cpu = cpu
            self.share = share
            self.startedBy = startedBy
            self.hint = hint
        }
    }

    public let memory: Memory
    public let tone: Pressure
    public let advice: String?
    public let tiles: [Tile]
    public let sectionTitle: String
    public var rows: [Row]
    public let updated: String
    // The login item is on, off, or unknown (nil hides it); set from live status, not the model.
    public var openAtLogin: Bool? = nil

    public init(memory: Memory, tone: Pressure, advice: String?, tiles: [Tile],
                sectionTitle: String, rows: [Row], updated: String) {
        self.memory = memory
        self.tone = tone
        self.advice = advice
        self.tiles = tiles
        self.sectionTitle = sectionTitle
        self.rows = rows
        self.updated = updated
    }
}

/// A line near the top of the panel, shown only when pressure is not normal.
let adviceByPressure: [Pressure: String] = [
    .warning: "Your Mac is starting to slow down. Quitting a heavy app below will help.",
    .critical: "Your Mac is short of memory. Quit an app below now.",
]

/// Advice by pressure alone: none when normal, otherwise a line near the top of the panel.
func adviceFor(_ pressure: Pressure) -> String? {
    pressure == .normal ? nil : adviceByPressure[pressure]
}

/// "HH:mm:ss" local 24-hour, zero-padded, matching the menu, forced to ASCII digits.
func formatTime(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
}

// Vendor words dropped before "by …" so the app's own name fits the row whole.
let vendorWords = ["Google", "Microsoft", "Mozilla", "Adobe"]

// Drop a leading vendor word from a short list before "by …" so the row keeps the app's name.
func withoutVendor(_ name: String) -> String {
    for word in vendorWords where name.hasPrefix("\(word) ") {
        let rest = name.dropFirst(word.count + 1)
        return rest.isEmpty ? name : String(rest)
    }
    return name
}

/// Builds the panel's plain data from a snapshot, leaving the snapshot untouched.
public func buildPanelView(_ snapshot: Snapshot, refreshSeconds: Int) -> PanelView {
    let memory = snapshot.memory
    let pressure = memory.pressure

    let mem = PanelView.Memory(
        percent: "\(Int(round(memory.usedPercent)))%",
        detail: "\(formatBytes(memory.usedBytes)) of \(formatBytes(memory.totalBytes))",
        help: "How much memory is in use. A high number is normal on a Mac.",
        barPercent: min(100, max(0, memory.usedPercent)))

    let top5 = groupByApp(snapshot.processes)
        .sorted { $0.memoryBytes > $1.memoryBytes }
        .prefix(5)
    let heaviest = top5.map(\.memoryBytes).max() ?? 0
    let rows = top5.map { g in
        let pid = g.mainPid ?? (g.pids.first ?? 0)
        let share = heaviest == 0 ? 0 : Double(g.memoryBytes) / Double(heaviest)
        // A copy another app started keeps the app's own name and shows the starter apart.
        let startedBy = g.startedBy
        let name = startedBy != nil ? withoutVendor(appName(g.bundlePath!)) : g.name
        return PanelView.Row(
            pid: pid,
            name: name,
            memory: formatBytes(g.memoryBytes),
            cpu: "\(fraction(g.cpu / Double(max(1, snapshot.cores))))%",
            share: share,
            startedBy: startedBy)
    }

    let tiles = [
        PanelView.Tile(
            label: "Pressure",
            value: pressure.rawValue.capitalized,
            help: "How hard your Mac is working to find free memory."),
        PanelView.Tile(
            label: "Swap",
            value: formatBytes(memory.swapUsedBytes),
            help: "Memory moved to the disk when it ran out of room. Many GB feels slower."),
        PanelView.Tile(
            label: "CPU",
            value: "\(Int(round(snapshot.cpuPercent)))%",
            help: "How busy the processor is right now."),
    ]

    return PanelView(
        memory: mem,
        tone: pressure,
        advice: adviceFor(pressure),
        tiles: tiles,
        sectionTitle: "Your apps using most memory",
        rows: Array(rows),
        updated: "Updated \(formatTime(snapshot.takenAt)) · refreshes every \(refreshSeconds) s")
}

/// The message, detail and button a quit confirmation shows.
public struct QuitPrompt: Equatable, Sendable {
    public let message: String
    public let detail: String
    public let button: String
}

/// The wording a quit confirmation shows, chosen by whether the group is an app.
public func quitPrompt(_ group: AppGroup) -> QuitPrompt {
    if let bundlePath = group.bundlePath {
        let count = group.pids.count
        let kind = count == 1 ? "process" : "processes"
        return QuitPrompt(
            message: "Quit \(group.name)?",
            detail: "This closes all its windows (\(count) \(kind), \(formatBytes(group.memoryBytes))).",
            button: "Quit App")
    }
    let pid = group.pids.first ?? 0
    return QuitPrompt(
        message: "Quit \"\(group.name)\"?",
        detail: "PID \(pid) · using \(formatBytes(group.memoryBytes)). Anything unsaved in it will be lost.",
        button: "Quit Process")
}
