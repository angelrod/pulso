// Tests for the panel's view model and the menu bar texts, translated from
// src/main/panel.test.ts and src/main/tray.test.ts. Three deliberate changes for 2.0:
// the update row is gone (Sparkle shows its own window); the section is titled "Your
// apps using most memory" (only the user's processes are readable); pressure and swap
// now live in MemoryReading.
import Foundation
import Testing
@testable import PulsoCore

private let total: UInt64 = 34_359_738_368

private func memory(usedPercent: Double = 70.3, pressure: Pressure = .normal) -> MemoryReading {
    MemoryReading(
        totalBytes: total,
        freeBytes: 10_200_547_328,
        usedBytes: UInt64((Double(total) * usedPercent / 100).rounded()),
        wiredBytes: 6_442_450_944,
        compressedBytes: 1_073_741_824,
        swapUsedBytes: 1_073_741_824,
        pressure: pressure)
}

private func at(_ h: Int, _ m: Int, _ s: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: h, minute: m, second: s))!
}

private let processes: [ProcessSample] = [
    ProcessSample(pid: 77, cpu: 3.5, memoryBytes: 120_000_000, command: "/usr/sbin/notifyd"),
    ProcessSample(pid: 4812, cpu: 92.1, memoryBytes: 1_500_000_000, command: "/usr/bin/mediaanalysisd"),
    ProcessSample(pid: 901, cpu: 12.0, memoryBytes: 750_000_000, command: "/Applications/Chrome.app/Contents/MacOS/Chrome"),
]

private func snapshot(_ mem: MemoryReading = memory(), _ procs: [ProcessSample] = processes) -> Snapshot {
    Snapshot(takenAt: at(15, 30, 5), memory: mem, cpuPercent: 18.4, processes: procs)
}

private func view(_ s: Snapshot = snapshot()) -> PanelView { buildPanelView(s, refreshSeconds: 3) }

@Suite("buildPanelView: memory")
struct PanelMemoryTests {
    @Test("leads with the whole percent and the amounts")
    func header() {
        let m = view().memory
        #expect(m.percent == "70%")
        #expect(m.detail == "22.5 GB of 32.0 GB")
        #expect(m.help == "How much memory is in use. A high number is normal on a Mac.")
    }

    @Test("fills the bar to the exact percent, kept between 0 and 100")
    func bar() {
        #expect(abs(view().memory.barPercent - 70.3) < 1e-6)
        #expect(view(snapshot(memory(usedPercent: 104))).memory.barPercent == 100)
    }
}

@Suite("buildPanelView: tone and advice")
struct PanelToneTests {
    @Test("takes its tone from memory pressure alone")
    func tone() {
        #expect(view().tone == .normal)
        #expect(view(snapshot(memory(pressure: .warning))).tone == .warning)
        #expect(view(snapshot(memory(pressure: .critical))).tone == .critical)
        #expect(view(snapshot(memory(usedPercent: 99))).tone == .normal)
    }

    @Test("gives advice only when pressure is not normal")
    func advice() {
        #expect(view().advice == nil)
        #expect(view(snapshot(memory(pressure: .warning))).advice
            == "Your Mac is starting to slow down. Quitting a heavy app below will help.")
        #expect(view(snapshot(memory(pressure: .critical))).advice
            == "Your Mac is short of memory. Quit an app below now.")
    }
}

@Suite("buildPanelView: tiles")
struct PanelTileTests {
    @Test("shows pressure, swap and cpu in that order, each with its explanation")
    func tiles() {
        #expect(view(snapshot(memory(pressure: .warning))).tiles == [
            PanelView.Tile(label: "Pressure", value: "Warning",
                           help: "How hard your Mac is working to find free memory."),
            PanelView.Tile(label: "Swap", value: "1.0 GB",
                           help: "Memory moved to the disk when it ran out of room. Many GB feels slower."),
            PanelView.Tile(label: "CPU", value: "18%", help: "How busy the processor is right now."),
        ])
    }
}

@Suite("buildPanelView: rows")
struct PanelRowTests {
    @Test("titles the list as the user's apps")
    func sectionTitle() {
        #expect(view().sectionTitle == "Your apps using most memory")
    }

    @Test("lists the heaviest by memory, by short name, with memory and cpu")
    func heaviest() {
        let rows = view().rows
        #expect(rows.map(\.pid) == [4812, 901, 77])
        #expect(rows[0] == PanelView.Row(pid: 4812, name: "mediaanalysisd", memory: "1.4 GB", cpu: "92.1%", share: 1))
        #expect(rows[1].name == "Chrome")
    }

    @Test("sizes each row's bar against the heaviest")
    func shares() {
        let rows = view().rows
        #expect(abs(rows[1].share - 0.5) < 1e-10)
        #expect(abs(rows[2].share - 0.08) < 1e-10)
    }

    @Test("shows at most five")
    func atMostFive() {
        var many: [ProcessSample] = []
        for i in 0..<9 {
            let bytes = UInt64(i + 1) * 1000
            many.append(ProcessSample(pid: Int32(100 + i), cpu: 0, memoryBytes: bytes, command: "/bin/p\(i)"))
        }
        #expect(view(snapshot(memory(), many)).rows.count == 5)
    }

    @Test("copes with no processes and with all of them at zero bytes")
    func empty() {
        #expect(view(snapshot(memory(), [])).rows.isEmpty)
        let zero = view(snapshot(memory(), [ProcessSample(pid: 9, cpu: 0, memoryBytes: 0, command: "/bin/z")]))
        #expect(zero.rows[0].share == 0)
    }

    @Test("sums an app's helpers into one row, keyed by the main process")
    func oneRowPerApp() {
        let app = "/Applications/Google Chrome.app"
        let rows = view(snapshot(memory(), [
            ProcessSample(pid: 760, cpu: 1, memoryBytes: 800_000_000, command: "\(app)/Contents/MacOS/Google Chrome"),
            ProcessSample(pid: 761, cpu: 2, memoryBytes: 700_000_000, command: "\(app)/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"),
            ProcessSample(pid: 77, cpu: 3.5, memoryBytes: 120_000_000, command: "/usr/sbin/notifyd"),
        ])).rows
        #expect(rows.map(\.name) == ["Google Chrome", "notifyd"])
        #expect(rows[0].pid == 760 && rows[0].memory == "1.4 GB" && rows[0].cpu == "3.0%" && rows[0].share == 1)
    }

    @Test("keys an app row by its first process when its main one is not running")
    func noMain() {
        let app = "/Applications/Google Chrome.app"
        let rows = view(snapshot(memory(), [
            ProcessSample(pid: 761, cpu: 0, memoryBytes: 700, command: "\(app)/Contents/Frameworks/H.app/Contents/MacOS/H"),
            ProcessSample(pid: 762, cpu: 0, memoryBytes: 100, command: "\(app)/Contents/Frameworks/G.app/Contents/MacOS/G"),
        ])).rows
        #expect(rows.count == 1 && rows[0].pid == 761)
    }

    @Test("ranks apps by their total, not by their biggest process")
    func rankByTotal() {
        let app = "/Applications/Google Chrome.app"
        let rows = view(snapshot(memory(), [
            ProcessSample(pid: 1, cpu: 0, memoryBytes: 500, command: "/bin/big"),
            ProcessSample(pid: 2, cpu: 0, memoryBytes: 300, command: "\(app)/Contents/MacOS/Google Chrome"),
            ProcessSample(pid: 3, cpu: 0, memoryBytes: 300, command: "\(app)/Contents/Frameworks/H.app/Contents/MacOS/H"),
        ])).rows
        #expect(rows.map(\.name) == ["Google Chrome", "big"])
    }
}

@Suite("buildPanelView: footer")
struct PanelFooterTests {
    @Test("says when the reading was taken and how often it refreshes")
    func footer() {
        #expect(view().updated == "Updated 15:30:05 · refreshes every 3 s")
        #expect(buildPanelView(snapshot(), refreshSeconds: 5).updated == "Updated 15:30:05 · refreshes every 5 s")
    }
}

@Suite("quitPrompt")
struct QuitPromptTests {
    @Test("says an app quits as a whole, with its processes and memory")
    func app() {
        let prompt = quitPrompt(AppGroup(name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app",
                                         pids: [760, 761, 762], mainPid: 760, memoryBytes: 1_500_000_000, cpu: 3))
        #expect(prompt == QuitPrompt(message: "Quit Google Chrome?",
                                     detail: "This closes all its windows (3 processes, 1.4 GB).", button: "Quit App"))
    }

    @Test("uses the singular for one process")
    func singular() {
        let prompt = quitPrompt(AppGroup(name: "Slack", bundlePath: "/Applications/Slack.app",
                                         pids: [900], mainPid: 900, memoryBytes: 1024 * 1024, cpu: 0))
        #expect(prompt.detail == "This closes all its windows (1 process, 1.0 MB).")
    }

    @Test("keeps today's wording for a process outside any app")
    func lone() {
        let prompt = quitPrompt(AppGroup(name: "node", bundlePath: nil, pids: [50], mainPid: 50,
                                         memoryBytes: 280 * 1024 * 1024, cpu: 3))
        #expect(prompt == QuitPrompt(message: "Quit \"node\"?",
                                     detail: "PID 50 · using 280.0 MB. Anything unsaved in it will be lost.",
                                     button: "Quit Process"))
    }
}

@Suite("menu bar item")
struct TrayTests {
    @Test("the title says what it measures, fits the bar, and ignores pressure")
    func title() {
        #expect(trayTitle(snapshot()) == "RAM 70%")
        #expect(trayTitle(snapshot()).count <= 12)
        for p in [Pressure.normal, .warning, .critical] {
            #expect(trayTitle(snapshot(memory(usedPercent: 100, pressure: p))) == "RAM 100%")
        }
    }

    @Test("the icon follows pressure alone; names match resources/")
    func icon() {
        #expect(trayIcon(snapshot(memory(usedPercent: 95))) == .template)
        #expect(trayIcon(snapshot(memory(pressure: .warning))) == .warning)
        #expect(trayIcon(snapshot(memory(pressure: .critical))) == .critical)
        #expect(TrayIcon.template.rawValue == "trayTemplate")
        #expect(TrayIcon.warning.rawValue == "trayWarning")
        #expect(TrayIcon.critical.rawValue == "trayCritical")
    }

    @Test("the tooltip spells out memory, cpu and swap")
    func tooltip() {
        let tip = trayTooltip(snapshot())
        #expect(tip == "Memory 22.5 GB of 32.0 GB · CPU 18.4% · Swap 1.0 GB")
    }
}

@Suite("helpDialog")
struct HelpDialogTests {
    @Test("has a title and explains every term the panel uses")
    func terms() {
        let help = helpDialog()
        #expect(help.message == "What do these mean?")
        for term in ["Memory used", "Memory pressure", "Swap", "CPU", "Your apps using most memory", "Icon colour"] {
            #expect(help.detail.contains(term), "missing \(term)")
        }
    }

    @Test("says what to do, not just what things are")
    func advice() {
        let detail = helpDialog().detail
        #expect(detail.contains("Closing a heavy app will help"))
        #expect(detail.contains("Click one to bring it to the front"))
        #expect(!detail.contains("one to watch"))
        #expect(detail.contains("Orange means warning"))
    }
}
